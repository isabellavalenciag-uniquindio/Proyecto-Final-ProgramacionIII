import Config

# En las pruebas no se escribe en disco: cada prueba trabaja solo en memoria.
config :emergencias, persistir: false

config :emergencias, EmergenciasWeb.Endpoint,
  server: false,
  check_origin: false,
  watchers: []

config :logger, level: :warning
