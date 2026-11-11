defmodule Necesidad do
  @moduledoc """
  Una solicitud de ayuda. Módulo puro: contiene las reglas de dominio
  (validación, transiciones de estado, orden por prioridad).

  ## Estados y transiciones válidas

      pendiente   -> asignada | cancelada
      asignada    -> en_atencion | cancelada
      en_atencion -> atendida | cancelada
      atendida    -> (final)
      cancelada   -> (final)

  Una necesidad cerrada (`atendida` o `cancelada`) no puede cerrarse dos veces
  ni volver a consumir recursos.

  ## Prioridad

  La prioridad **ordena** las solicitudes: `insertar_ordenado/2` mantiene la
  lista de más crítica a menos crítica y, a igual prioridad, la más antigua
  primero.
  """

  @enforce_keys [:id, :tipo, :cantidad, :prioridad, :zona, :responsable]
  defstruct [
    :id,
    :tipo,
    :cantidad,
    :prioridad,
    :zona,
    :responsable,
    descripcion: "",
    estado: :pendiente,
    asignaciones: []
  ]

  @tipos [:agua, :alimentos, :medicamentos, :primeros_auxilios, :refugio, :transporte, :rescate, :otra]
  @prioridades [:critica, :alta, :media, :baja]
  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  @doc "Tipos de necesidad válidos."
  def tipos, do: @tipos
  @doc "Prioridades válidas, de mayor a menor."
  def prioridades, do: @prioridades
  @doc "Estados válidos."
  def estados, do: @estados

  @doc """
  Crea una necesidad validando los datos.

  ## Ejemplo

      iex> {:ok, n} = Necesidad.nuevo("N001", "agua", 30, "crítica", "centro", "Punto 3", "laura")
      iex> {n.tipo, n.prioridad, n.estado}
      {:agua, :critica, :pendiente}
  """
  @spec nuevo(String.t(), term(), term(), term(), term(), term(), term()) ::
          {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(id, tipo, cantidad, prioridad, zona, descripcion, responsable) do
    with {:ok, tipo} <- Validacion.atomo(tipo, @tipos, :tipo_invalido),
         {:ok, cantidad} <- Validacion.entero_positivo(cantidad),
         {:ok, prioridad} <- Validacion.atomo(prioridad, @prioridades, :prioridad_invalida),
         {:ok, zona} <- Validacion.texto(zona),
         {:ok, responsable} <- Validacion.texto(responsable) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         cantidad: cantidad,
         prioridad: prioridad,
         zona: zona,
         responsable: responsable,
         descripcion: descripcion |> to_string() |> String.trim()
       }}
    end
  end

  @doc "Cantidad ya asignada con recursos."
  @spec total_asignado(%__MODULE__{}) :: non_neg_integer()
  def total_asignado(%__MODULE__{asignaciones: asignaciones}) do
    Enum.reduce(asignaciones, 0, fn {_codigo, _ubicacion, n}, acc -> acc + n end)
  end

  @doc "Cantidad que aún falta por asignar."
  @spec faltante(%__MODULE__{}) :: non_neg_integer()
  def faltante(%__MODULE__{} = n), do: n.cantidad - total_asignado(n)

  @doc """
  Registra recursos reservados. Solo una necesidad `pendiente` puede recibir
  recursos, y nunca más de lo que le falta. Al completar la cantidad pasa a
  `asignada`.
  """
  @spec asignar(%__MODULE__{}, [{String.t(), String.t(), pos_integer()}]) ::
          {:ok, %__MODULE__{}} | {:error, atom()}
  def asignar(%__MODULE__{estado: :pendiente} = n, detalle) do
    total = Enum.reduce(detalle, 0, fn {_c, _u, cantidad}, acc -> acc + cantidad end)

    if total > faltante(n) do
      {:error, :excede_requerida}
    else
      actualizada = %{n | asignaciones: n.asignaciones ++ detalle}
      estado = if faltante(actualizada) == 0, do: :asignada, else: :pendiente
      {:ok, %{actualizada | estado: estado}}
    end
  end

  def asignar(%__MODULE__{}, _detalle), do: {:error, :estado_invalido}

  @doc """
  Cambia el estado respetando las transiciones válidas.
  Una necesidad cerrada devuelve `{:error, :ya_cerrada}`.
  """
  @spec cambiar_estado(%__MODULE__{}, term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def cambiar_estado(%__MODULE__{estado: actual} = n, nuevo) do
    with {:ok, nuevo} <- Validacion.atomo(nuevo, @estados, :estado_invalido) do
      cond do
        actual in [:atendida, :cancelada] -> {:error, :ya_cerrada}
        nuevo in Map.fetch!(@transiciones, actual) -> {:ok, %{n | estado: nuevo}}
        true -> {:error, :transicion_invalida}
      end
    end
  end

  @doc "Número consecutivo del identificador (`\"N007\"` -> 7)."
  @spec numero(%__MODULE__{}) :: non_neg_integer()
  def numero(%__MODULE__{id: id}), do: id |> String.trim_leading("N") |> String.to_integer()

  @doc """
  Inserta una necesidad en una lista ya ordenada, manteniendo el orden por
  prioridad y luego por antigüedad. Recursiva de cola.

  ## Ejemplo

      iex> {:ok, baja} = Necesidad.nuevo("N001", :agua, 1, :baja, "z", "", "ana")
      iex> {:ok, critica} = Necesidad.nuevo("N002", :agua, 1, :critica, "z", "", "ana")
      iex> [baja] |> Necesidad.insertar_ordenado(critica) |> Enum.map(& &1.id)
      ["N002", "N001"]
  """
  @spec insertar_ordenado([%__MODULE__{}], %__MODULE__{}) :: [%__MODULE__{}]
  def insertar_ordenado(lista, nueva), do: insertar(lista, nueva, [])

  defp insertar([], nueva, previos), do: Enum.reverse([nueva | previos])

  defp insertar([actual | resto] = lista, nueva, previos) do
    if va_antes?(nueva, actual) do
      Enum.reverse(previos, [nueva | lista])
    else
      insertar(resto, nueva, [actual | previos])
    end
  end

  defp va_antes?(a, b), do: {peso(a.prioridad), numero(a)} < {peso(b.prioridad), numero(b)}

  defp peso(prioridad), do: Enum.find_index(@prioridades, &(&1 == prioridad))

  # ---------- Persistencia ----------

  @doc "Convierte la necesidad en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = n) do
    asignaciones =
      n.asignaciones
      |> Enum.map(fn {codigo, ubicacion, cantidad} ->
        Enum.join([Archivo.sanear_item(codigo), Archivo.sanear_item(ubicacion), cantidad], ":")
      end)
      |> Archivo.lista_a_texto()

    [
      n.id,
      to_string(n.tipo),
      to_string(n.cantidad),
      to_string(n.prioridad),
      Archivo.sanear(n.zona),
      Archivo.sanear(n.descripcion),
      Archivo.sanear(n.responsable),
      to_string(n.estado),
      asignaciones
    ]
  end

  @doc "Reconstruye una necesidad desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([id, tipo, cantidad, prioridad, zona, descripcion, responsable, estado, asignaciones]) do
    %__MODULE__{
      id: id,
      tipo: a_atomo(tipo, @tipos),
      cantidad: String.to_integer(cantidad),
      prioridad: a_atomo(prioridad, @prioridades),
      zona: zona,
      descripcion: descripcion,
      responsable: responsable,
      estado: a_atomo(estado, @estados),
      asignaciones:
        asignaciones
        |> Archivo.texto_a_lista()
        |> Enum.map(fn texto ->
          [codigo, ubicacion, n] = String.split(texto, ":")
          {codigo, ubicacion, String.to_integer(n)}
        end)
    }
  end

  defp a_atomo(texto, validos), do: Enum.find(validos, &(Atom.to_string(&1) == texto))
end

