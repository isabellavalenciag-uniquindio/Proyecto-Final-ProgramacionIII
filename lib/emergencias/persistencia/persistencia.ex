defmodule Persistencia do
  @moduledoc """
  Proceso que serializa el acceso a los archivos.

  Aunque varios procesos pidan guardar al mismo tiempo, las escrituras se
  atienden una por una, así dos procesos nunca escriben el mismo archivo a la
  vez. Los demás GenServer cargan su estado de aquí en `init/1` (por eso un
  proceso reiniciado por su supervisor recupera sus datos) y guardan tras
  cada cambio.
  """
  use GenServer
  require Logger

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Devuelve las filas guardadas de una entidad."
  @spec cargar(atom()) :: [[String.t()]]
  def cargar(entidad), do: GenServer.call(__MODULE__, {:cargar, entidad})

  @doc "Reemplaza todo el archivo de la entidad (no espera respuesta)."
  @spec guardar(atom(), [[term()]]) :: :ok
  def guardar(entidad, filas), do: GenServer.cast(__MODULE__, {:guardar, entidad, filas})

  @doc "Inserta o reemplaza una sola fila, identificada por su primera columna."
  @spec guardar_fila(atom(), [term()]) :: :ok
  def guardar_fila(entidad, fila), do: GenServer.cast(__MODULE__, {:guardar_fila, entidad, fila})

  @doc "Espera a que se terminen de escribir todas las peticiones pendientes."
  @spec sincronizar() :: :ok
  def sincronizar, do: GenServer.call(__MODULE__, :sincronizar)

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:cargar, entidad}, _from, estado) do
    {:reply, Archivo.leer(entidad), estado}
  end

  def handle_call(:sincronizar, _from, estado), do: {:reply, :ok, estado}

  @impl true
  def handle_cast({:guardar, entidad, filas}, estado) do
    entidad |> Archivo.escribir(filas) |> registrar_error(entidad)
    {:noreply, estado}
  end

  def handle_cast({:guardar_fila, entidad, fila}, estado) do
    entidad |> Archivo.guardar_fila(fila) |> registrar_error(entidad)
    {:noreply, estado}
  end

  defp registrar_error(:ok, _entidad), do: :ok

  defp registrar_error({:error, razon}, entidad) do
    Logger.error("No se pudo guardar #{entidad}: #{inspect(razon)}")
  end
end
