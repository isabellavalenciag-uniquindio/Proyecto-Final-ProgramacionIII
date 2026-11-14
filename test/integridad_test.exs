defmodule IntegridadTest do
  use ExUnit.Case

  test "las APIs rechazan referencias a zonas inexistentes sin crear registros" do
    id = "inexistente#{System.unique_integer([:positive])}"
    error = {:error, {:zona_inexistente, id}}
    assert ^error = Personas.reportar(id, "Ana", id, :localizada)
    assert ^error = Mascotas.reportar(:perdida, "perro", "Luna", "negro", :mediano, id, "300")
    assert ^error = Necesidades.registrar(:agua, 5, :alta, id, "Ayuda", "ana")
    assert ^error = Albergues.registrar(id, "Norte", id, 5)
    assert ^error = Inventario.registrar(id, "Agua", "agua", 5, "litros", id, id)
    assert {:error, :no_existe} = Personas.obtener(id)
    assert Mascotas.listar(zona: id) == []
    assert Necesidades.listar(zona: id) == []
    assert {:error, :no_existe} = Albergues.consultar(id)
    assert Inventario.listar(codigo: id) == []
  end

  test "un albergue no guarda asociaciones con recursos o necesidades inexistentes" do
    id = "asociacion#{System.unique_integer([:positive])}"
    {:ok, _} = Zonas.registrar(id, "Zona", :alto)
    {:ok, _} = Albergues.registrar(id, "Norte", id, 5)
    assert {:error, {:recurso_inexistente, ^id}} = Albergues.asociar_recurso(id, id)
    assert {:error, {:necesidad_inexistente, ^id}} = Albergues.asociar_necesidad(id, id)
    assert {:ok, %{recursos: [], necesidades: []}} = Albergues.consultar(id)
  end

  test "la consola informa zonas inexistentes al reportar personas y mascotas" do
    id = "consola#{System.unique_integer([:positive])}"
    {:ok, _, sesion} = Emergencias.ejecutar("connect #{id} 1234 ciudadano #{id}", Emergencias.nueva_sesion())
    for comando <- ["report_person #{id} Ana #{id} localizada",
                    "report_pet found perro Luna negro mediano #{id} 300"] do
      assert {:error, texto, _} = Emergencias.ejecutar(comando, sesion)
      assert texto =~ "no existe"
    end
  end
end
