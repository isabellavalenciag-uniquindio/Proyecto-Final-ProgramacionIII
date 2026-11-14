import Config

if datos = System.get_env("EMERGENCIAS_DATOS_DIR") do
  config :emergencias, datos_dir: datos
end

if config_env() != :test do
  port = String.to_integer(System.get_env("PORT", "4000"))
  config :emergencias, EmergenciasWeb.Endpoint, http: [ip: {127, 0, 0, 1}, port: port]

  if config_env() == :dev do
    config :emergencias, EmergenciasWeb.Endpoint,
      check_origin: ["//localhost:#{port}", "//127.0.0.1:#{port}"]
  end
end

if System.get_env("PHX_SERVER") do
  config :emergencias, EmergenciasWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret =
    System.get_env("SECRET_KEY_BASE") ||
      raise "Defina SECRET_KEY_BASE para iniciar NEXO en producción."

  host = System.get_env("PHX_HOST", "localhost")

  config :emergencias, EmergenciasWeb.Endpoint,
    secret_key_base: secret,
    url: [host: host, scheme: "https", port: 443],
    check_origin: ["https://#{host}"]

  config :emergencias, :cookie_segura, true
end
