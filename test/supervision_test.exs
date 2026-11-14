defmodule SupervisionTest do
  use ExUnit.Case

  defp esperar(funcion, intentos \\ 200)
  defp esperar(_funcion, 0), do: flunk("No se recuperaron los albergues a tiempo")
  defp esperar(funcion, intentos) do
    if funcion.() do
      :ok
    else
      Process.sleep(10)
      esperar(funcion, intentos - 1)
    end
  end

  for dependencia <- [AlbergueSupervisor, Emergencias.RegistroAlbergues] do
    @dependencia dependencia
    test "recupera ocupantes y asociaciones al caer #{inspect(dependencia)}" do
      id = "recuperar#{System.unique_integer([:positive])}"
      {:ok, _} = Zonas.registrar(id, "Zona", :alto)
      {:ok, _} = Inventario.registrar(id, "Agua", "agua", 5, "litros", id, id)
      {:ok, n} = Necesidades.registrar(:agua, 5, :alta, id, "", "ana")
      for codigo <- [id, id <> "sur"] do
        {:ok, _} = Albergues.registrar(codigo, "Albergue", id, 5)
        {:ok, _} = Albergues.ingresar(codigo, codigo <> "persona")
        {:ok, _} = Albergues.asociar_recurso(codigo, id)
        {:ok, _} = Albergues.asociar_necesidad(codigo, n.id)
      end
      :ok = Persistencia.sincronizar()
      {:ok, anterior} = AlbergueProceso.consultar(id)
      [{anterior_pid, _}] = Registry.lookup(Emergencias.RegistroAlbergues, id)
      pid = Process.whereis(@dependencia)
      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
      esperar(fn ->
        nuevo = Process.whereis(@dependencia)
        recuperador = Process.whereis(AlbergueRecuperador)
        is_pid(nuevo) and nuevo != pid and is_pid(recuperador) and
          match?({:ok, _}, Albergues.consultar(id <> "sur"))
      end)
      assert {:ok, ^anterior} = AlbergueProceso.consultar(id)
      assert [{nuevo_pid, _}] = Registry.lookup(Emergencias.RegistroAlbergues, id)
      assert nuevo_pid != anterior_pid
      assert {:error, :en_otro_albergue} = Albergues.ingresar(id <> "sur", id <> "persona")
    end
  end
end
