defmodule EmergenciasWeb do
  @moduledoc "Puntos de entrada de la interfaz Phoenix de NEXO."
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html], layouts: []
      import Plug.Conn
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: false, log: false
      import EmergenciasWeb.Componentes
      import EmergenciasWeb.Secciones
      alias EmergenciasWeb.Operaciones
      alias EmergenciasWeb.Presentacion
    end
  end

  defmacro __using__(tipo), do: apply(__MODULE__, tipo, [])
end
