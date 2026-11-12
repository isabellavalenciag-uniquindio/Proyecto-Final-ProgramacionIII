defmodule Zona do
  @moduledoc """
  Jerarquía de una zona afectada: **zona → sectores → puntos de atención**.

  Los tres niveles usan el mismo struct (`tipo` indica cuál es), lo que
  permite recorrerlos con funciones recursivas. Cada nodo guarda el número
  estimado de personas afectadas *directamente* en él; `estadisticas/1` suma
  el nodo con todo lo que cuelga de él.

  ## Funciones recursivas

  `buscar/2`, `agregar/3`, `estadisticas/1`, `acumulado/1`, `por_nivel/2`,
  `a_filas/1` y `desde_filas/1` recorren el árbol llamándose a sí mismas
  sobre cada hijo.
  """

  @enforce_keys [:codigo, :nombre, :tipo, :nivel]
  defstruct [:codigo, :nombre, :tipo, :nivel, afectados: 0, hijos: []]

  @niveles [:critico, :alto, :medio, :bajo]
  @tipos [:zona, :sector, :punto]
  # Qué tipo de hijo admite cada tipo de nodo
  @hijo_de %{zona: :sector, sector: :punto}

  @doc "Niveles de afectación válidos."
  def niveles, do: @niveles

  @doc "Crea una zona (raíz del árbol)."
  @spec nueva(term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nueva(codigo, nombre, nivel, afectados \\ 0), do: crear(:zona, codigo, nombre, nivel, afectados)

  @doc "Crea un sector (hijo de una zona)."
  @spec nuevo_sector(term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo_sector(codigo, nombre, nivel, afectados \\ 0), do: crear(:sector, codigo, nombre, nivel, afectados)

  @doc "Crea un punto de atención (hijo de un sector)."
  @spec nuevo_punto(term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo_punto(codigo, nombre, nivel, afectados \\ 0), do: crear(:punto, codigo, nombre, nivel, afectados)

  defp crear(tipo, codigo, nombre, nivel, afectados) do
    with {:ok, codigo} <- Validacion.texto(codigo),
         {:ok, nombre} <- Validacion.texto(nombre),
         {:ok, nivel} <- Validacion.atomo(nivel, @niveles, :nivel_invalido),
         {:ok, afectados} <- Validacion.entero_no_negativo(afectados) do
      {:ok, %__MODULE__{codigo: codigo, nombre: nombre, tipo: tipo, nivel: nivel, afectados: afectados}}
    end
  end

  @doc """
  Busca un nodo por código en todo el árbol. **Recursiva.**

  ## Ejemplo

      iex> {:ok, z} = Zona.nueva("c", "Centro", :alto, 100)
      iex> {:ok, s} = Zona.nuevo_sector("s1", "Sector 1", :critico, 40)
      iex> {:ok, z} = Zona.agregar(z, "c", s)
      iex> {:ok, nodo} = Zona.buscar(z, "s1")
      iex> nodo.nombre
      "Sector 1"
  """
  @spec buscar(%__MODULE__{}, String.t()) :: {:ok, %__MODULE__{}} | {:error, :no_existe}
  def buscar(%__MODULE__{codigo: codigo} = nodo, codigo), do: {:ok, nodo}

  def buscar(%__MODULE__{hijos: hijos}, codigo) do
    Enum.find_value(hijos, {:error, :no_existe}, fn hijo ->
      case buscar(hijo, codigo) do
        {:ok, _} = encontrado -> encontrado
        {:error, _} -> nil
      end
    end)
  end

  @doc """
  Agrega un nodo bajo el padre indicado, respetando la jerarquía
  (zona → sector → punto) y sin repetir códigos en el árbol.
  """
  @spec agregar(%__MODULE__{}, String.t(), %__MODULE__{}) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def agregar(%__MODULE__{} = raiz, padre_codigo, %__MODULE__{} = hijo) do
    case {buscar(raiz, hijo.codigo), buscar(raiz, padre_codigo)} do
      {{:ok, _}, _} ->
        {:error, :codigo_duplicado}

      {_, {:error, :no_existe}} ->
        {:error, :padre_no_existe}

      {_, {:ok, padre}} ->
        if Map.get(@hijo_de, padre.tipo) == hijo.tipo do
          {:ok, insertar(raiz, padre_codigo, hijo)}
        else
          {:error, :jerarquia_invalida}
        end
    end
  end

  # Recursiva: baja por el árbol hasta el padre y le agrega el hijo
  defp insertar(%__MODULE__{codigo: codigo} = nodo, codigo, hijo) do
    %{nodo | hijos: nodo.hijos ++ [hijo]}
  end

  defp insertar(%__MODULE__{} = nodo, padre, hijo) do
    %{nodo | hijos: Enum.map(nodo.hijos, &insertar(&1, padre, hijo))}
  end

  @doc "Personas afectadas del nodo más las de todos sus descendientes. **Recursiva.**"
  @spec acumulado(%__MODULE__{}) :: non_neg_integer()
  def acumulado(%__MODULE__{afectados: afectados, hijos: hijos}) do
    Enum.reduce(hijos, afectados, fn hijo, acc -> acc + acumulado(hijo) end)
  end

  @doc """
  Estadísticas acumuladas del nodo y todo lo que cuelga de él: personas
  afectadas, cantidad de sectores y cantidad de puntos de atención.
  **Recursiva.**
  """
  @spec estadisticas(%__MODULE__{}) :: %{afectados: integer(), sectores: integer(), puntos: integer()}
  def estadisticas(%__MODULE__{} = nodo) do
    base = %{
      afectados: nodo.afectados,
      sectores: if(nodo.tipo == :sector, do: 1, else: 0),
      puntos: if(nodo.tipo == :punto, do: 1, else: 0)
    }

    Enum.reduce(nodo.hijos, base, fn hijo, acc ->
      Map.merge(acc, estadisticas(hijo), fn _clave, a, b -> a + b end)
    end)
  end

  @doc "Lista los nodos (zona, sectores y puntos) con un nivel de afectación dado. **Recursiva.**"
  @spec por_nivel(%__MODULE__{}, atom()) :: [%__MODULE__{}]
  def por_nivel(%__MODULE__{nivel: nivel, hijos: hijos} = nodo, buscado) do
    propios = if nivel == buscado, do: [nodo], else: []
    propios ++ Enum.flat_map(hijos, &por_nivel(&1, buscado))
  end

  # ---------- Persistencia ----------

  @doc """
  Aplana el árbol en filas `[zona, padre, codigo, nombre, tipo, nivel, afectados]`.
  El padre de la zona raíz es `""`. **Recursiva.**
  """
  @spec a_filas(%__MODULE__{}) :: [[String.t()]]
  def a_filas(%__MODULE__{} = raiz), do: aplanar(raiz, raiz.codigo, "")

  defp aplanar(nodo, raiz, padre) do
    fila = [
      Archivo.sanear(raiz),
      Archivo.sanear(padre),
      Archivo.sanear(nodo.codigo),
      Archivo.sanear(nodo.nombre),
      to_string(nodo.tipo),
      to_string(nodo.nivel),
      to_string(nodo.afectados)
    ]

    [fila | Enum.flat_map(nodo.hijos, &aplanar(&1, raiz, nodo.codigo))]
  end

  @doc "Reconstruye los árboles (uno por zona) desde las filas aplanadas. **Recursiva.**"
  @spec desde_filas([[String.t()]]) :: [%__MODULE__{}]
  def desde_filas(filas) do
    filas
    |> Enum.filter(fn [_raiz, padre | _] -> padre == "" end)
    |> Enum.map(&construir(&1, filas))
  end

  defp construir([raiz, _padre, codigo, nombre, tipo, nivel, afectados], filas) do
    hijos =
      filas
      |> Enum.filter(fn [r, p | _] -> r == raiz and p == codigo end)
      |> Enum.map(&construir(&1, filas))

    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      tipo: a_atomo(tipo, @tipos),
      nivel: a_atomo(nivel, @niveles),
      afectados: String.to_integer(afectados),
      hijos: hijos
    }
  end

  defp a_atomo(texto, validos), do: Enum.find(validos, &(Atom.to_string(&1) == texto))
end
