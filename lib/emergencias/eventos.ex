defmodule Emergencias.Eventos do
  @moduledoc "Notificaciones de cambios del dominio para las interfaces conectadas."
  @topic "emergencias:datos"

  def suscribir, do: Phoenix.PubSub.subscribe(Emergencias.PubSub, @topic)

  def notificar(entidad) do
    if Process.whereis(Emergencias.PubSub) do
      Phoenix.PubSub.broadcast(Emergencias.PubSub, @topic, {:datos_actualizados, entidad})
    end

    :ok
  end
end
