defmodule Personas do
  @moduledoc """
  Proceso que guarda las personas afectadas y los mensajes entre familiares.

  Estado: `%{personas: %{documento => %Persona{}}, mensajes: [%Mensaje{}]}`.
  Se usa un mapa para las personas porque se buscan por documento, y una lista
  para los mensajes porque se conservan en orden de llegada.
  """
  use GenServer

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Registra una persona. Error `:duplicado` si ya existe ese documento."
  @spec reportar(term(), term(), term(), term(), term()) :: {:ok, %Persona{}} | {:error, atom()}
  def reportar(documento, nombre, zona, estado, edad \\ 0) do
    GenServer.call(__MODULE__, {:reportar, documento, nombre, zona, estado, edad})
  end

  @doc "Busca una persona por documento."
  @spec obtener(String.t()) :: {:ok, %Persona{}} | {:error, :no_existe}
  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, documento})

  @doc "Busca personas. Filtros opcionales: `nombre:` (parcial), `documento:`, `zona:`, `estado:`."
  @spec buscar(keyword()) :: [%Persona{}]
  def buscar(filtros \\ []), do: GenServer.call(__MODULE__, {:buscar, filtros})

  @doc "Todas las personas."
  @spec listar() :: [%Persona{}]
  def listar, do: buscar([])

  @doc "Cambia el estado de una persona respetando las transiciones válidas."
  @spec actualizar_estado(String.t(), term()) :: {:ok, %Persona{}} | {:error, atom()}
  def actualizar_estado(documento, estado), do: GenServer.call(__MODULE__, {:estado, documento, estado})

  @doc "Historial de estados de una persona, el más reciente primero."
  @spec historial(String.t()) :: {:ok, [{atom(), String.t()}]} | {:error, :no_existe}
  def historial(documento) do
    with {:ok, persona} <- obtener(documento), do: {:ok, persona.historial}
  end

  @doc "Deja un mensaje para una persona (por documento)."
  @spec enviar_mensaje(term(), term(), term()) :: {:ok, %Mensaje{}} | {:error, atom()}
  def enviar_mensaje(remitente, destinatario, contenido) do
    GenServer.call(__MODULE__, {:mensaje, remitente, destinatario, contenido})
  end

  @doc "Mensajes dirigidos a un documento (o todos si es `nil`), en orden de llegada."
  @spec mensajes(String.t() | nil) :: [%Mensaje{}]
  def mensajes(documento \\ nil), do: GenServer.call(__MODULE__, {:mensajes, documento})

  @doc "Marca un mensaje como entregado."
  @spec marcar_entregado(integer()) :: {:ok, %Mensaje{}} | {:error, atom()}
  def marcar_entregado(id), do: GenServer.call(__MODULE__, {:entregar, id})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    personas =
      :personas |> Persistencia.cargar() |> Enum.map(&Persona.desde_fila/1) |> Map.new(&{&1.documento, &1})

    mensajes = :mensajes |> Persistencia.cargar() |> Enum.map(&Mensaje.desde_fila/1)
    {:ok, %{personas: personas, mensajes: mensajes}}
  end

  @impl true
  def handle_call({:reportar, documento, nombre, zona, estado, edad}, _from, estado_proc) do
    with {:ok, persona} <- Persona.nuevo(documento, nombre, zona, estado, edad),
         :ok <- Zonas.validar(persona.zona),
         false <- Map.has_key?(estado_proc.personas, persona.documento) do
      {:reply, {:ok, persona}, guardar_personas(estado_proc, Map.put(estado_proc.personas, persona.documento, persona))}
    else
      true -> {:reply, {:error, :duplicado}, estado_proc}
      {:error, _} = error -> {:reply, error, estado_proc}
    end
  end

  def handle_call({:obtener, documento}, _from, estado_proc) do
    {:reply, buscar_persona(estado_proc.personas, documento), estado_proc}
  end

  def handle_call({:buscar, filtros}, _from, estado_proc) do
    lista =
      estado_proc.personas
      |> Map.values()
      |> Enum.filter(fn p -> Enum.all?(filtros, &Persona.cumple?(p, &1)) end)
      |> Enum.sort_by(& &1.documento)

    {:reply, lista, estado_proc}
  end

  def handle_call({:estado, documento, estado}, _from, estado_proc) do
    with {:ok, persona} <- buscar_persona(estado_proc.personas, documento),
         {:ok, nueva} <- Persona.cambiar_estado(persona, estado) do
      {:reply, {:ok, nueva}, guardar_personas(estado_proc, Map.put(estado_proc.personas, nueva.documento, nueva))}
    else
      {:error, _} = error -> {:reply, error, estado_proc}
    end
  end

  def handle_call({:mensaje, remitente, destinatario, contenido}, _from, estado_proc) do
    case Mensaje.nuevo(siguiente_id(estado_proc.mensajes), remitente, destinatario, contenido) do
      {:ok, mensaje} -> {:reply, {:ok, mensaje}, guardar_mensajes(estado_proc, estado_proc.mensajes ++ [mensaje])}
      {:error, _} = error -> {:reply, error, estado_proc}
    end
  end

  def handle_call({:mensajes, nil}, _from, estado_proc), do: {:reply, estado_proc.mensajes, estado_proc}

  def handle_call({:mensajes, documento}, _from, estado_proc) do
    lista = Enum.filter(estado_proc.mensajes, &Validacion.coincide?(&1.destinatario, documento))
    {:reply, lista, estado_proc}
  end

  def handle_call({:entregar, id}, _from, estado_proc) do
    with {:ok, mensaje} <- buscar_mensaje(estado_proc.mensajes, id),
         {:ok, entregado} <- Mensaje.marcar_entregado(mensaje) do
      mensajes = Enum.map(estado_proc.mensajes, fn m -> if m.id == id, do: entregado, else: m end)
      {:reply, {:ok, entregado}, guardar_mensajes(estado_proc, mensajes)}
    else
      {:error, _} = error -> {:reply, error, estado_proc}
    end
  end

  # ========== Funciones auxiliares ==========

  defp buscar_persona(personas, documento) do
    case Map.fetch(personas, to_string(documento) |> String.trim()) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, :no_existe}
    end
  end

  defp buscar_mensaje(mensajes, id) do
    case Enum.find(mensajes, &(&1.id == id)) do
      nil -> {:error, :no_existe}
      mensaje -> {:ok, mensaje}
    end
  end

  defp siguiente_id(mensajes), do: (mensajes |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)) + 1

  defp guardar_personas(estado, personas) do
    filas = personas |> Map.values() |> Enum.sort_by(& &1.documento) |> Enum.map(&Persona.a_fila/1)
    Persistencia.guardar(:personas, filas)
    %{estado | personas: personas}
  end

  defp guardar_mensajes(estado, mensajes) do
    Persistencia.guardar(:mensajes, Enum.map(mensajes, &Mensaje.a_fila/1))
    %{estado | mensajes: mensajes}
  end
end
