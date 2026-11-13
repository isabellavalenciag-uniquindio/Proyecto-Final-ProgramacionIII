defmodule Persona do
  @moduledoc """
  Una persona afectada y el historial de sus cambios de estado. Módulo puro.

  ## Estados y transiciones

      sin_informacion -> reportada | localizada | trasladada | en_albergue | reunificada
      reportada       -> localizada | trasladada | en_albergue | reunificada
      localizada      -> trasladada | en_albergue | reunificada
      trasladada      -> localizada | en_albergue | reunificada
      en_albergue     -> trasladada | reunificada
      reunificada     -> (final)

  Una persona `reunificada` no puede cambiar de estado otra vez.
  """

  @enforce_keys [:documento, :nombre, :zona, :estado]
  defstruct [:documento, :nombre, :zona, :estado, edad: 0, historial: []]

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @transiciones %{
    sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue, :reunificada],
    reportada: [:localizada, :trasladada, :en_albergue, :reunificada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:trasladada, :reunificada],
    reunificada: []
  }

  @doc "Estados válidos."
  def estados, do: @estados

  @doc """
  Crea una persona. El documento sirve de identificador y no puede repetirse
  (eso lo controla el proceso `Personas`).

  ## Ejemplo

      iex> {:ok, p} = Persona.nuevo("123", "Andrés", "zona_norte", "localizada", 30)
      iex> {p.estado, length(p.historial)}
      {:localizada, 1}
  """
  @spec nuevo(term(), term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(documento, nombre, zona, estado, edad \\ 0) do
    with {:ok, documento} <- Validacion.texto(documento),
         {:ok, nombre} <- Validacion.texto(nombre),
         {:ok, zona} <- Validacion.texto(zona),
         {:ok, estado} <- Validacion.atomo(estado, @estados, :estado_invalido),
         {:ok, edad} <- validar_edad(edad) do
      {:ok,
       %__MODULE__{
         documento: documento,
         nombre: nombre,
         zona: zona,
         estado: estado,
         edad: edad,
         historial: [{estado, ahora()}]
       }}
    end
  end

  @doc """
  Cambia el estado respetando las transiciones válidas y lo anota en el
  historial (el más reciente primero).
  """
  @spec cambiar_estado(%__MODULE__{}, term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def cambiar_estado(%__MODULE__{} = p, nuevo) do
    with {:ok, nuevo} <- Validacion.atomo(nuevo, @estados, :estado_invalido) do
      cond do
        p.estado == :reunificada -> {:error, :ya_cerrada}
        nuevo == p.estado -> {:error, :mismo_estado}
        nuevo in Map.fetch!(@transiciones, p.estado) -> {:ok, %{p | estado: nuevo, historial: [{nuevo, ahora()} | p.historial]}}
        true -> {:error, :transicion_invalida}
      end
    end
  end

  @doc """
  Indica si la persona cumple un filtro `{campo, valor}`.
  `:nombre` busca por coincidencia parcial; los demás campos, por igualdad.
  """
  @spec cumple?(%__MODULE__{}, {atom(), term()}) :: boolean()
  def cumple?(%__MODULE__{nombre: nombre}, {:nombre, valor}) do
    String.contains?(Validacion.normalizar(nombre), Validacion.normalizar(valor))
  end

  def cumple?(%__MODULE__{} = p, {campo, valor}) when campo in [:documento, :zona, :estado] do
    Validacion.coincide?(Map.fetch!(p, campo), valor)
  end

  def cumple?(%__MODULE__{}, _otro), do: true

  @doc "Fecha y hora local como texto ISO (sin espacios), p. ej. `2026-11-10T21:18:00`."
  @spec ahora() :: String.t()
  def ahora, do: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp validar_edad(edad) do
    case Validacion.entero_no_negativo(edad) do
      {:ok, n} when n <= 130 -> {:ok, n}
      _ -> {:error, :edad_invalida}
    end
  end

  # ---------- Persistencia ----------

  @doc "Convierte la persona en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = p) do
    historial = p.historial |> Enum.map(fn {estado, fecha} -> "#{estado}@#{fecha}" end) |> Archivo.lista_a_texto()

    [
      Archivo.sanear(p.documento),
      Archivo.sanear(p.nombre),
      to_string(p.edad),
      Archivo.sanear(p.zona),
      to_string(p.estado),
      historial
    ]
  end

  @doc "Reconstruye una persona desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([documento, nombre, edad, zona, estado, historial]) do
    %__MODULE__{
      documento: documento,
      nombre: nombre,
      edad: String.to_integer(edad),
      zona: zona,
      estado: a_atomo(estado),
      historial:
        historial
        |> Archivo.texto_a_lista()
        |> Enum.map(fn item ->
          [e, fecha] = String.split(item, "@")
          {a_atomo(e), fecha}
        end)
    }
  end

  defp a_atomo(texto), do: Enum.find(@estados, &(Atom.to_string(&1) == texto))
end
