import Config

# Configuración general. La de pruebas está en config/test.exs
if config_env() == :test, do: import_config("test.exs")
