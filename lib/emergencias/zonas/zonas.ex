defmodule Zonas do
  @moduledoc """
  Proceso que guarda las zonas afectadas con su jerarquía
  (zona → sectores → puntos de atención).

  El estado es un mapa `%{codigo_zona => %Zona{}}`. Toda la lógica del árbol
  vive en el módulo puro `Zona`; este proceso solo guarda y persiste.
  """
  use GenServer

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Registra una zona con su nivel de afectación y personas afectadas estimadas."
  @spec registrar(term(), term(), term(), term()) :: {:ok, %Zona{}} | {:error, atom()}
  def registrar(codigo, nombre, nivel, afectados \\ 0) do
    GenServer.call(__MODULE__, {:registrar, codigo, nombre, nivel, afectados})
  end

  @doc "Agrega un sector a una zona."
  @spec agregar_sector(String.t(), term(), term(), term(), term()) :: {:ok, %Zona{}} | {:error, atom()}
  def agregar_sector(zona, codigo, nombre, nivel, afectados \\ 0) do
    GenServer.call(__MODULE__, {:agregar_sector, zona, codigo, nombre, nivel, afectados})
  end

  @doc "Agrega un punto de atención a un sector. Hereda el nivel del sector."
  @spec agregar_punto(String.t(), String.t(), term(), term(), term()) :: {:ok, %Zona{}} | {:error, atom()}
  def agregar_punto(zona, sector, codigo, nombre, afectados \\ 0) do
    GenServer.call(__MODULE__, {:agregar_punto, zona, sector, codigo, nombre, afectados})
  end

  @doc "Devuelve el árbol completo de una zona."
  @spec obtener(String.t()) :: {:ok, %Zona{}} | {:error, :no_existe}
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})

  @doc "Indica si existe la zona."
  @spec existe?(String.t()) :: boolean()
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))

  @doc "Valida una referencia a una zona registrada."
  @spec validar(String.t()) :: :ok | {:error, {:zona_inexistente, String.t()}}
  def validar(codigo) do
    if existe?(codigo), do: :ok, else: {:error, {:zona_inexistente, codigo}}
  end

  @doc "Lista todas las zonas."
  @spec listar() :: [%Zona{}]
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Estadísticas acumuladas de la zona (recorre sectores y puntos)."
  @spec estadisticas(String.t()) :: {:ok, map()} | {:error, :no_existe}
  def estadisticas(codigo) do
    with {:ok, zona} <- obtener(codigo), do: {:ok, Zona.estadisticas(zona)}
  end

  @doc "Estado general de la zona: datos, estadísticas totales y resumen por sector."
  @spec estado(String.t()) :: {:ok, map()} | {:error, :no_existe}
  def estado(codigo) do
    with {:ok, zona} <- obtener(codigo) do
      {:ok,
       %{
         codigo: zona.codigo,
         nombre: zona.nombre,
         nivel: zona.nivel,
         estadisticas: Zona.estadisticas(zona),
         sectores:
           Enum.map(zona.hijos, fn s ->
             %{codigo: s.codigo, nombre: s.nombre, nivel: s.nivel, estadisticas: Zona.estadisticas(s)}
           end)
       }}
    end
  end

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    zonas =
      :zonas
      |> Persistencia.cargar()
      |> Zona.desde_filas()
      |> Map.new(fn z -> {z.codigo, z} end)

    {:ok, zonas}
  end

  @impl true
  def handle_call({:registrar, codigo, nombre, nivel, afectados}, _from, zonas) do
    with {:ok, zona} <- Zona.nueva(codigo, nombre, nivel, afectados),
         :ok <- no_existe(zonas, zona.codigo) do
      {:reply, {:ok, zona}, guardar(Map.put(zonas, zona.codigo, zona))}
    else
      {:error, _} = error -> {:reply, error, zonas}
    end
  end

  def handle_call({:agregar_sector, zona, codigo, nombre, nivel, afectados}, _from, zonas) do
    with {:ok, raiz} <- buscar(zonas, zona),
         {:ok, sector} <- Zona.nuevo_sector(codigo, nombre, nivel, afectados),
         {:ok, nueva} <- Zona.agregar(raiz, raiz.codigo, sector) do
      {:reply, {:ok, nueva}, guardar(Map.put(zonas, nueva.codigo, nueva))}
    else
      {:error, _} = error -> {:reply, error, zonas}
    end
  end

  def handle_call({:agregar_punto, zona, sector, codigo, nombre, afectados}, _from, zonas) do
    with {:ok, raiz} <- buscar(zonas, zona),
         {:ok, padre} <- Zona.buscar(raiz, sector) |> padre_existe(),
         {:ok, punto} <- Zona.nuevo_punto(codigo, nombre, padre.nivel, afectados),
         {:ok, nueva} <- Zona.agregar(raiz, sector, punto) do
      {:reply, {:ok, nueva}, guardar(Map.put(zonas, nueva.codigo, nueva))}
    else
      {:error, _} = error -> {:reply, error, zonas}
    end
  end

  def handle_call({:obtener, codigo}, _from, zonas), do: {:reply, buscar(zonas, codigo), zonas}

  def handle_call(:listar, _from, zonas) do
    {:reply, zonas |> Map.values() |> Enum.sort_by(& &1.codigo), zonas}
  end

  # ========== Funciones auxiliares ==========

  defp buscar(zonas, codigo) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, :no_existe}
    end
  end

  defp no_existe(zonas, codigo) do
    if Map.has_key?(zonas, codigo), do: {:error, :duplicado}, else: :ok
  end

  defp padre_existe({:ok, _} = ok), do: ok
  defp padre_existe({:error, :no_existe}), do: {:error, :padre_no_existe}

  defp guardar(zonas) do
    filas =
      zonas
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)
      |> Enum.flat_map(&Zona.a_filas/1)

    Persistencia.guardar(:zonas, filas)
    zonas
  end
end
