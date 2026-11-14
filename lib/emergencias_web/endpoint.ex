defmodule EmergenciasWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :emergencias

  @session_options [
    store: :cookie,
    key: "_nexo_session",
    signing_salt: "nexo_cookie_firma",
    encryption_salt: "nexo_cookie_cifrado",
    same_site: "Lax",
    http_only: true,
    max_age: 28_800
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :emergencias,
    gzip: false,
    only: ~w(assets favicon.svg robots.txt)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 1_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug :iniciar_sesion
  plug EmergenciasWeb.Router

  defp iniciar_sesion(conn, _) do
    opciones =
      Keyword.put(
        @session_options,
        :secure,
        Application.get_env(:emergencias, :cookie_segura, false)
      )

    Plug.Session.call(conn, Plug.Session.init(opciones))
  end
end
