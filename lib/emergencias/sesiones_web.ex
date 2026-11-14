defmodule Emergencias.SesionesWeb do
  @moduledoc """
  Relaciona un token aleatorio del navegador con una sesión emitida por Usuarios.
  Las credenciales y los roles no se guardan en la cookie. Cada consulta vuelve
  a validar la sesión original; las sesiones web caducan después de ocho horas.
  """
  use GenServer
  @duracion 8 * 60 * 60

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def crear(sesion), do: GenServer.call(__MODULE__, {:crear, sesion})
  def obtener(token) when is_binary(token), do: GenServer.call(__MODULE__, {:obtener, token})
  def obtener(_), do: {:error, :sin_sesion}
  def cerrar(token), do: GenServer.call(__MODULE__, {:cerrar, token})

  def socket_id(token),
    do: "sesiones:" <> Base.url_encode64(:crypto.hash(:sha256, token), padding: false)

  @impl true
  def init(_) do
    Process.send_after(self(), :limpiar, 60_000)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:crear, %{usuario: usuario} = sesion}, _from, sesiones) do
    case Usuarios.validar_sesion(usuario) do
      {:ok, _} ->
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        {:reply, {:ok, token}, Map.put(sesiones, token, {sesion, ahora() + @duracion})}

      error ->
        {:reply, error, sesiones}
    end
  end

  def handle_call({:crear, _}, _from, sesiones), do: {:reply, {:error, :sin_sesion}, sesiones}

  def handle_call({:obtener, token}, _from, sesiones) do
    case validar(Map.get(sesiones, token)) do
      {:ok, sesion} ->
        {:reply, {:ok, sesion}, sesiones}

      _ ->
        desconectar(Map.get(sesiones, token))
        {:reply, {:error, :sin_sesion}, Map.delete(sesiones, token)}
    end
  end

  def handle_call({:cerrar, token}, _from, sesiones) do
    desconectar(Map.get(sesiones, token))

    if is_binary(token),
      do: EmergenciasWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})

    {:reply, :ok, Map.delete(sesiones, token)}
  end

  @impl true
  def handle_info(:limpiar, sesiones) do
    {vigentes, vencidas} = Enum.split_with(sesiones, fn {_, {_, vence}} -> vence > ahora() end)

    Enum.each(vencidas, fn {token, entrada} ->
      desconectar(entrada)
      EmergenciasWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})
    end)

    Process.send_after(self(), :limpiar, 60_000)
    {:noreply, Map.new(vigentes)}
  end

  defp validar({%{usuario: usuario} = sesion, vence}) do
    with true <- vence > ahora(),
         {:ok, actual} <- Usuarios.validar_sesion(usuario) do
      {:ok, %{sesion | usuario: actual}}
    else
      _ -> {:error, :sin_sesion}
    end
  end

  defp validar(_), do: {:error, :sin_sesion}

  defp desconectar({%{usuario: u}, _}), do: Usuarios.desconectar(u.usuario, u.sesion_id)
  defp desconectar(_), do: :ok
  defp ahora, do: System.monotonic_time(:second)
end
