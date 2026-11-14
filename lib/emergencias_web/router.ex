defmodule EmergenciasWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmergenciasWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws://localhost:* ws://127.0.0.1:*; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    }
  end

  scope "/", EmergenciasWeb do
    pipe_through :browser
    live "/acceso", AccesoLive, :index
    post "/sesion", SesionController, :crear
    post "/salir", SesionController, :cerrar
    live "/", PanelLive, :inicio
    live "/panel/:seccion", PanelLive, :seccion
  end
end
