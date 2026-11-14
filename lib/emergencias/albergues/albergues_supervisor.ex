defmodule AlberguesSupervisor do
  @moduledoc """
  Supervisa las dependencias de los albergues en orden `:rest_for_one`.
  Si cae el Registry, se reconstruyen los procesos y sus nombres; si cae
  el supervisor dinámico, se vuelve a ejecutar la recuperación de albergues.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([
      %{id: Emergencias.RegistroAlbergues,
        start: {__MODULE__, :iniciar_registro, []}, type: :supervisor},
      AlbergueSupervisor,
      AlbergueRecuperador
    ], strategy: :rest_for_one)
  end

  @doc false
  def iniciar_registro do
    case Registry.start_link(keys: :unique, name: Emergencias.RegistroAlbergues) do
      {:error, {:shutdown, {:failed_to_start_child, _, {:already_started, pid}}}} ->
        # Al morir el supervisor del Registry, sus particiones pueden tardar
        # en liberar sus nombres. Esperar su salida evita agotar los reinicios.
        monitor = Process.monitor(pid)
        receive do
          {:DOWN, ^monitor, :process, ^pid, _} -> iniciar_registro()
        after
          5_000 ->
            Process.demonitor(monitor, [:flush])
            {:error, :registro_no_disponible}
        end
      resultado -> resultado
    end
  end
end

defmodule AlbergueRecuperador do
  @moduledoc "Carga los albergues cuando sus dependencias arrancan o se reinician."
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case Albergues.cargar() do
      :ok -> {:ok, nil}
      {:error, razon} -> {:stop, razon}
    end
  end
end
