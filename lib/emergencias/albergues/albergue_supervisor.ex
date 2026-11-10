defmodule AlbergueSupervisor do
  @moduledoc """
  `DynamicSupervisor` de los albergues. Empieza sin hijos y agrega un
  `AlbergueProceso` cada vez que se registra un albergue, porque su cantidad no
  se conoce de antemano.

  Con la estrategia `:one_for_one`, si un albergue falla solo se reinicia ese;
  los demás siguen atendiendo.
  """
  use DynamicSupervisor

  def start_link(_opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Inicia el proceso de un albergue. Error `:duplicado` si el código ya existe."
  @spec iniciar_albergue(%Albergue{}) :: {:ok, pid()} | {:error, atom() | term()}
  def iniciar_albergue(%Albergue{} = albergue) do
    case DynamicSupervisor.start_child(__MODULE__, {AlbergueProceso, albergue}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :duplicado}
      {:error, _} = error -> error
    end
  end
end
