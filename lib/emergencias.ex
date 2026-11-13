defmodule Emergencias do
  @moduledoc """
  Sistema distribuido de coordinación y gestión de emergencias (terremoto).

  Este módulo es la puerta de entrada pública: reúne las operaciones que usan
  la consola, las pruebas y el video de demostración.

  ## Uso

      iex -S mix
      iex> Emergencias.iniciar()
  """

  @doc "Abre la consola interactiva."
  @spec iniciar() :: :ok
  defdelegate iniciar, to: Consola, as: :main

  @doc "Sesión nueva, sin usuario conectado."
  @spec nueva_sesion() :: map()
  def nueva_sesion, do: %{usuario: nil}

  @doc "Ejecuta una línea de comando sobre una sesión. Ver `Comandos.ejecutar/2`."
  @spec ejecutar(String.t(), map()) :: {:ok | :error | :salir, String.t(), map()}
  defdelegate ejecutar(linea, sesion), to: Comandos

  @doc """
  Demostración del conflicto concurrente: hay 50 litros de agua y dos
  coordinadores piden a la vez 30 y 25 litros. Solo una asignación se
  confirma y el inventario nunca baja de 0.

  Devuelve los dos resultados y las existencias finales.
  """
  @spec demo_conflicto() :: map()
  def demo_conflicto do
    n = System.unique_integer([:positive])
    zona = "demo#{n}"
    categoria = "agua#{n}"

    {:ok, _} = Zonas.registrar(zona, "Zona demo", :critico, 100)
    {:ok, _} = Inventario.registrar("R#{n}", "Agua", categoria, 50, "litros", "centro_acopio_#{n}")
    {:ok, a} = Necesidades.registrar(:agua, 30, :critica, zona, "Punto de atención sector 3", "laura")
    {:ok, b} = Necesidades.registrar(:agua, 25, :alta, zona, "Albergue norte", "pedro")

    solicitudes = [{"laura", a.id, 30}, {"pedro", b.id, 25}]

    resultados =
      solicitudes
      |> Enum.map(fn {usuario, id, cantidad} ->
        Task.async(fn ->
          {:ok, _, sesion} = ejecutar("connect #{usuario}#{n} 1234 coordinador #{zona}", nueva_sesion())
          {_estado, texto, _} = ejecutar("assign_resource #{id} #{categoria} #{cantidad}", sesion)
          {usuario, cantidad, texto}
        end)
      end)
      |> Task.await_many()

    %{resultados: resultados, existencias_finales: Inventario.disponibilidad(categoria)}
  end
end
