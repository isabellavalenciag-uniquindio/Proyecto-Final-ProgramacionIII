defmodule Consola do
  @moduledoc """
  Interfaz de consola: lee una línea, la pasa a `Comandos` y muestra el
  resultado, hasta que el usuario escribe `exit`.

  El bucle es recursivo de cola: la sesión viaja como argumento de una vuelta
  a la siguiente.

  Se ejecuta con `iex -S mix` y luego `Consola.main()`, o directamente con

      mix run -e "Consola.main()"
  """

  @doc "Inicia la consola."
  @spec main() :: :ok
  def main do
    Util2.mostrar("=== Sistema de Coordinación y Gestión de Emergencias ===", :mensaje)
    Util2.mostrar("Escriba help para ver los comandos. Para empezar: connect usuario contraseña tipo zona\n", :mensaje)
    bucle(%{usuario: nil})
  end

  defp bucle(sesion) do
    linea = leer(prompt(sesion))

    case Comandos.ejecutar(linea, sesion) do
      {:salir, texto, _sesion} ->
        Util2.mostrar(texto, :mensaje)

      {:ok, texto, nueva} ->
        mostrar(texto, :mensaje)
        bucle(nueva)

      {:error, texto, nueva} ->
        mostrar(texto, :error)
        bucle(nueva)
    end
  end

  defp prompt(%{usuario: nil}), do: "emergencias> "
  defp prompt(%{usuario: %{usuario: nombre, tipo: tipo}}), do: "#{nombre} (#{tipo})> "

  # Si se cierra la entrada (Ctrl+D) se trata como "exit"
  defp leer(prompt) do
    case IO.gets(prompt) do
      :eof -> "exit"
      {:error, _} -> "exit"
      texto -> String.trim(texto)
    end
  end

  defp mostrar("", _tipo), do: :ok
  defp mostrar(texto, tipo), do: Util2.mostrar(texto, tipo)
end
