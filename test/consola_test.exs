defmodule ConsolaTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "muestra el saludo y termina con exit" do
    salida = capture_io([input: "exit\n"], fn -> Consola.main() end)
    assert salida =~ "Sistema de Coordinación"
    assert salida =~ "Hasta pronto"
  end

  test "ejecuta comandos y mantiene la sesión entre líneas" do
    n = System.unique_integer([:positive])
    entrada = "connect consola#{n} 1234 ciudadano norte\nhelp\nexit\n"
    salida = capture_io([input: entrada], fn -> Consola.main() end)

    assert salida =~ "registrado y conectado"
    assert salida =~ "consola#{n} (ciudadano)>"
    assert salida =~ "register_need"
  end

  test "si se cierra la entrada, la consola termina sola" do
    salida = capture_io([input: ""], fn -> Consola.main() end)
    assert salida =~ "Hasta pronto"
  end

  test "un comando inválido no detiene la consola" do
    salida = capture_io([input: "volar\nexit\n"], fn -> Consola.main() end)
    assert salida =~ "Hasta pronto"
  end
end
