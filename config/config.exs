import Config

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["password", "clave", "token"]

config :emergencias, EmergenciasWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "nexo_solo_desarrollo_cambiar_en_produccion_0123456789abcdef0123456789abcdef",
  render_errors: [formats: [html: EmergenciasWeb.ErrorHTML], layout: false],
  pubsub_server: Emergencias.PubSub,
  live_view: [signing_salt: "nexo_live_view"]

config :esbuild,
  version: "0.25.12",
  default: [
    args: ~w(assets/js/app.js --bundle --target=es2020 --outdir=priv/static/assets/vendor),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

if config_env() == :dev do
  config :emergencias, EmergenciasWeb.Endpoint,
    debug_errors: true,
    check_origin: ["//localhost:4000", "//127.0.0.1:4000"],
    watchers: [esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]}]
end

if config_env() == :test, do: import_config("test.exs")
