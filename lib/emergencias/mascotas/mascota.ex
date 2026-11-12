defmodule Mascota do
  @moduledoc """
  Reporte de una mascota perdida o encontrada y el algoritmo de coincidencias.
  Módulo puro.

  ## Estados

  `:activa` → `:posible_coincidencia` → `:resuelta`. Un reporte `:resuelta` no
  puede resolverse otra vez.

  ## Puntaje de similitud (0 a 100)

  Se compara una mascota perdida con una encontrada. Si la especie es
  distinta, el puntaje es 0. Si no, se suman estos criterios, cada uno
  multiplicado por su afinidad (un número entre 0 y 1):

  | Criterio          | Peso | Afinidad                                           |
  |-------------------|------|----------------------------------------------------|
  | especie           | 30   | 1 si es igual                                      |
  | color             | 20   | 1 si es igual                                      |
  | zona              | 20   | 1 si es igual                                      |
  | tamaño            | 15   | 1 si es igual, 0.5 si es contiguo (mediano/grande) |
  | nombre            | 10   | 1 si ambos lo conocen y coinciden                  |
  | características   | 5    | palabras en común sobre el total (Jaccard)         |

  Se considera posible coincidencia desde 60 puntos (`umbral/0`).
  """

  @enforce_keys [:id, :tipo, :especie, :color, :tamano, :zona, :contacto]
  defstruct [
    :id, :tipo, :especie, :color, :tamano, :zona, :contacto,
    nombre: "desconocido", caracteristicas: "", estado: :activa, coincidencia: nil
  ]

  @tipos [:perdida, :encontrada]
  @tamanos [:pequeno, :mediano, :grande]
  @estados [:activa, :posible_coincidencia, :resuelta]
  @umbral 60
  @criterios [especie: 30, color: 20, zona: 20, tamano: 15, nombre: 10, caracteristicas: 5]

  @doc "Puntaje mínimo para considerar una posible coincidencia."
  def umbral, do: @umbral

  @doc """
  Crea un reporte. El tipo acepta `perdida`/`lost` y `encontrada`/`found`.
  El nombre puede ser `desconocido`.

  ## Ejemplo

      iex> {:ok, m} = Mascota.nuevo("M001", "lost", "perro", "Luna", "negra", "mediana", "zona_norte", "300123")
      iex> {m.tipo, m.tamano, m.estado}
      {:perdida, :mediano, :activa}
  """
  @spec nuevo(String.t(), term(), term(), term(), term(), term(), term(), term(), term()) ::
          {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(id, tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas \\ "") do
    with {:ok, tipo} <- Validacion.atomo(alias_tipo(tipo), @tipos, :tipo_invalido),
         {:ok, especie} <- Validacion.texto(especie),
         {:ok, color} <- Validacion.texto(color),
         {:ok, tamano} <- Validacion.atomo(alias_tamano(tamano), @tamanos, :tamano_invalido),
         {:ok, zona} <- Validacion.texto(zona),
         {:ok, contacto} <- Validacion.texto(contacto) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         especie: especie,
         nombre: nombre_o_desconocido(nombre),
         color: color,
         tamano: tamano,
         zona: zona,
         contacto: contacto,
         caracteristicas: caracteristicas |> to_string() |> String.trim()
       }}
    end
  end

  defp alias_tipo(tipo) when is_binary(tipo) do
    case Validacion.normalizar(tipo) do
      "lost" -> "perdida"
      "found" -> "encontrada"
      otro -> otro
    end
  end

  defp alias_tipo(tipo), do: tipo

  # Permite escribir "pequeña", "mediana" o "grande" (femenino)
  defp alias_tamano(tamano) when is_binary(tamano) do
    case Validacion.normalizar(tamano) do
      "pequena" -> "pequeno"
      "mediana" -> "mediano"
      otro -> otro
    end
  end

  defp alias_tamano(tamano), do: tamano

  defp nombre_o_desconocido(nombre) do
    case Validacion.texto(nombre) do
      {:ok, texto} -> texto
      {:error, _} -> "desconocido"
    end
  end

  @doc "Marca un reporte activo como posible coincidencia (los demás no cambian)."
  @spec marcar_posible(%__MODULE__{}) :: %__MODULE__{}
  def marcar_posible(%__MODULE__{estado: :activa} = m), do: %{m | estado: :posible_coincidencia}
  def marcar_posible(%__MODULE__{} = m), do: m

  @doc "Cierra el reporte indicando con cuál otro coincidió. No se puede cerrar dos veces."
  @spec resolver(%__MODULE__{}, String.t()) :: {:ok, %__MODULE__{}} | {:error, :ya_resuelta}
  def resolver(%__MODULE__{estado: :resuelta}, _otro_id), do: {:error, :ya_resuelta}
  def resolver(%__MODULE__{} = m, otro_id), do: {:ok, %{m | estado: :resuelta, coincidencia: otro_id}}

  @doc """
  Puntaje de similitud entre dos reportes, de 0 a 100. **Recursiva de cola**
  sobre la lista de criterios, acumulando el puntaje.

  ## Ejemplos

      iex> {:ok, a} = Mascota.nuevo("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte", "1")
      iex> {:ok, b} = Mascota.nuevo("M2", :encontrada, "perro", "", "negra", "mediana", "norte", "2")
      iex> Mascota.similitud(a, b)
      85

      iex> {:ok, a} = Mascota.nuevo("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte", "1")
      iex> {:ok, g} = Mascota.nuevo("M3", :encontrada, "gato", "", "negra", "mediana", "norte", "2")
      iex> Mascota.similitud(a, g)
      0
  """
  @spec similitud(%__MODULE__{}, %__MODULE__{}) :: non_neg_integer()
  def similitud(%__MODULE__{} = a, %__MODULE__{} = b) do
    if afinidad(:especie, a, b) == 1.0, do: a |> puntuar(b, @criterios, 0.0) |> round(), else: 0
  end

  defp puntuar(_a, _b, [], acumulado), do: acumulado

  defp puntuar(a, b, [{criterio, peso} | resto], acumulado) do
    puntuar(a, b, resto, acumulado + peso * afinidad(criterio, a, b))
  end

  defp afinidad(:especie, a, b), do: igual(a.especie, b.especie)
  defp afinidad(:color, a, b), do: igual(a.color, b.color)
  defp afinidad(:zona, a, b), do: igual(a.zona, b.zona)

  defp afinidad(:tamano, a, b) do
    case abs(indice(a.tamano) - indice(b.tamano)) do
      0 -> 1.0
      1 -> 0.5
      _ -> 0.0
    end
  end

  defp afinidad(:nombre, a, b) do
    if conocido?(a.nombre) and conocido?(b.nombre), do: igual(a.nombre, b.nombre), else: 0.0
  end

  defp afinidad(:caracteristicas, a, b), do: jaccard(palabras(a.caracteristicas), palabras(b.caracteristicas))

  defp igual(x, y), do: if(Validacion.coincide?(x, y), do: 1.0, else: 0.0)
  defp conocido?(nombre), do: Validacion.normalizar(nombre) != "desconocido"
  defp indice(tamano), do: Enum.find_index(@tamanos, &(&1 == tamano))

  defp palabras(texto) do
    texto
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> MapSet.new()
  end

  defp jaccard(a, b) do
    union = MapSet.union(a, b) |> MapSet.size()
    if union == 0, do: 0.0, else: MapSet.intersection(a, b) |> MapSet.size() |> Kernel./(union)
  end

  @doc """
  Pares (perdida, encontrada) cuyo puntaje llega al umbral, de mayor a menor
  puntaje. Solo considera reportes que no estén resueltos.
  """
  @spec coincidencias([%__MODULE__{}], non_neg_integer()) :: [map()]
  def coincidencias(lista, umbral \\ @umbral) do
    {perdidas, encontradas} = separar(lista)

    perdidas
    |> Enum.flat_map(&pares_de(&1, encontradas, umbral))
    |> ordenar()
  end

  @doc "Igual que `coincidencias/2`, pero compara cada perdida en un proceso distinto (`Task.async_stream`)."
  @spec coincidencias_paralelo([%__MODULE__{}], non_neg_integer()) :: [map()]
  def coincidencias_paralelo(lista, umbral \\ @umbral) do
    {perdidas, encontradas} = separar(lista)

    perdidas
    |> Task.async_stream(&pares_de(&1, encontradas, umbral), timeout: 30_000)
    |> Enum.flat_map(fn {:ok, pares} -> pares end)
    |> ordenar()
  end

  defp separar(lista) do
    abiertas = Enum.reject(lista, &(&1.estado == :resuelta))
    {Enum.filter(abiertas, &(&1.tipo == :perdida)), Enum.filter(abiertas, &(&1.tipo == :encontrada))}
  end

  defp pares_de(perdida, encontradas, umbral) do
    encontradas
    |> Enum.map(fn e -> %{perdida: perdida.id, encontrada: e.id, puntaje: similitud(perdida, e)} end)
    |> Enum.filter(&(&1.puntaje >= umbral))
  end

  defp ordenar(pares), do: Enum.sort_by(pares, &{-&1.puntaje, &1.perdida, &1.encontrada})

  @doc "Indica si el reporte cumple un filtro `{campo, valor}` (`:especie`, `:zona`, `:estado`, `:tipo`)."
  @spec cumple?(%__MODULE__{}, {atom(), term()}) :: boolean()
  def cumple?(%__MODULE__{} = m, {campo, valor}) when campo in [:especie, :zona, :estado, :tipo] do
    Validacion.coincide?(Map.fetch!(m, campo), alias_tipo(valor))
  end

  def cumple?(%__MODULE__{}, _otro), do: true

  # ---------- Persistencia ----------

  @doc "Convierte el reporte en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = m) do
    [
      m.id, to_string(m.tipo), Archivo.sanear(m.especie), Archivo.sanear(m.nombre),
      Archivo.sanear(m.caracteristicas), Archivo.sanear(m.color), to_string(m.tamano),
      Archivo.sanear(m.zona), Archivo.sanear(m.contacto), to_string(m.estado), m.coincidencia || ""
    ]
  end

  @doc "Reconstruye un reporte desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado, coincidencia]) do
    %__MODULE__{
      id: id,
      tipo: a_atomo(tipo, @tipos),
      especie: especie,
      nombre: nombre,
      caracteristicas: caracteristicas,
      color: color,
      tamano: a_atomo(tamano, @tamanos),
      zona: zona,
      contacto: contacto,
      estado: a_atomo(estado, @estados),
      coincidencia: if(coincidencia == "", do: nil, else: coincidencia)
    }
  end

  defp a_atomo(texto, validos), do: Enum.find(validos, &(Atom.to_string(&1) == texto))
end
