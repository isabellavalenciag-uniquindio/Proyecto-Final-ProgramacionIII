defmodule Recurso do
  @moduledoc """
  Un recurso guardado en un lugar concreto (centro de acopio, albergue...).

  La identidad de un recurso es la pareja `{codigo, ubicacion}`: el mismo
  código (por ejemplo `R001`) puede existir en varios lugares, lo que permite
  las transferencias entre centros.

  Todas las funciones son puras: reciben un recurso y devuelven uno nuevo, sin
  guardar nada. Los errores esperados se devuelven como `{:error, razon}`.
  """

  @enforce_keys [:codigo, :nombre, :categoria, :unidad, :ubicacion]
  defstruct [:codigo, :nombre, :categoria, :unidad, :ubicacion, :zona, cantidad: 0, movimientos: []]

  @tipos_movimiento [
    :alta,
    :entrada,
    :salida,
    :reserva,
    :liberacion,
    :transferencia_entrada,
    :transferencia_salida
  ]

  @doc """
  Crea un recurso validando todos los datos. La cantidad inicial puede ser 0
  pero nunca negativa.

  ## Ejemplo

      iex> {:ok, r} = Recurso.nuevo("R001", "Agua", "agua", 200, "litros", "centro_1")
      iex> r.cantidad
      200
  """
  @spec nuevo(term(), term(), term(), term(), term(), term(), term()) ::
          {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona \\ nil) do
    with {:ok, codigo} <- Validacion.texto(codigo),
         {:ok, nombre} <- Validacion.texto(nombre),
         {:ok, categoria} <- Validacion.texto(categoria),
         {:ok, unidad} <- Validacion.texto(unidad),
         {:ok, ubicacion} <- Validacion.texto(ubicacion),
         {:ok, cantidad} <- Validacion.entero_no_negativo(cantidad),
         {:ok, zona} <- validar_zona(zona) do
      recurso = %__MODULE__{
        codigo: codigo,
        nombre: nombre,
        categoria: categoria,
        unidad: unidad,
        ubicacion: ubicacion,
        zona: zona,
        cantidad: cantidad
      }

      {:ok, registrar_movimiento(recurso, :alta, cantidad)}
    end
  end

  defp validar_zona(nil), do: {:ok, nil}
  defp validar_zona(zona), do: Validacion.texto(zona)

  @doc "Clave única del recurso: `{codigo, ubicacion}`."
  @spec clave(%__MODULE__{}) :: {String.t(), String.t()}
  def clave(%__MODULE__{codigo: codigo, ubicacion: ubicacion}), do: {codigo, ubicacion}

  @doc "Indica si la clave dada es el código o la categoría del recurso."
  @spec coincide?(%__MODULE__{}, term()) :: boolean()
  def coincide?(%__MODULE__{} = r, clave) do
    Validacion.coincide?(r.codigo, clave) or Validacion.coincide?(r.categoria, clave)
  end

  @doc """
  Comprueba el tipo de ayuda que puede cubrir el recurso. Una categoría de
  necesidad conocida tiene prioridad; para categorías personalizadas se usa
  el nombre del recurso (por ejemplo, Agua en la categoría agua_potable).
  """
  @spec compatible?(%__MODULE__{}, atom()) :: boolean()
  def compatible?(%__MODULE__{} = r, tipo) do
    case Validacion.atomo(r.categoria, Necesidad.tipos()) do
      {:ok, categoria} -> categoria == tipo
      {:error, _} -> Validacion.coincide?(r.nombre, tipo)
    end
  end

  @doc "Suma unidades al recurso. Rechaza cantidades que no sean positivas."
  @spec sumar(%__MODULE__{}, term(), atom()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def sumar(%__MODULE__{} = r, n, tipo \\ :entrada) when tipo in @tipos_movimiento do
    with {:ok, n} <- Validacion.entero_positivo(n) do
      {:ok, registrar_movimiento(%{r | cantidad: r.cantidad + n}, tipo, n)}
    end
  end

  @doc "Resta unidades. Nunca deja la cantidad en negativo: devuelve `{:error, :insuficiente}`."
  @spec restar(%__MODULE__{}, term(), atom()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def restar(%__MODULE__{} = r, n, tipo \\ :salida) when tipo in @tipos_movimiento do
    with {:ok, n} <- Validacion.entero_positivo(n) do
      if n > r.cantidad do
        {:error, :insuficiente}
      else
        {:ok, registrar_movimiento(%{r | cantidad: r.cantidad - n}, tipo, n)}
      end
    end
  end

  # El historial guarda el movimiento más reciente primero
  defp registrar_movimiento(%__MODULE__{} = r, tipo, cantidad) do
    movimiento = {tipo, cantidad, Date.to_string(Date.utc_today())}
    %{r | movimientos: [movimiento | r.movimientos]}
  end

  # ---------- Persistencia ----------

  @doc "Convierte el recurso en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = r) do
    movimientos =
      r.movimientos
      |> Enum.map(fn {tipo, n, fecha} -> "#{tipo}:#{n}:#{fecha}" end)
      |> Archivo.lista_a_texto()

    [
      Archivo.sanear(r.codigo),
      Archivo.sanear(r.nombre),
      Archivo.sanear(r.categoria),
      to_string(r.cantidad),
      Archivo.sanear(r.unidad),
      Archivo.sanear(r.ubicacion),
      movimientos,
      Archivo.sanear(r.zona || "")
    ]
  end

  @doc "Reconstruye un recurso desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([codigo, nombre, categoria, cantidad, unidad, ubicacion, movimientos]) do
    desde_fila([codigo, nombre, categoria, cantidad, unidad, ubicacion, movimientos, ""])
  end

  def desde_fila([codigo, nombre, categoria, cantidad, unidad, ubicacion, movimientos, zona]) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      categoria: categoria,
      cantidad: String.to_integer(cantidad),
      unidad: unidad,
      ubicacion: ubicacion,
      zona: if(zona == "", do: nil, else: zona),
      movimientos: movimientos |> Archivo.texto_a_lista() |> Enum.map(&movimiento_desde_texto/1)
    }
  end

  defp movimiento_desde_texto(texto) do
    [tipo, n, fecha] = String.split(texto, ":")
    {Enum.find(@tipos_movimiento, :entrada, &(Atom.to_string(&1) == tipo)), String.to_integer(n), fecha}
  end
end
