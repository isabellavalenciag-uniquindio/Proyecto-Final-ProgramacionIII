defmodule ReportesTest do
  use ExUnit.Case

  setup do
    n = System.unique_integer([:positive])
    {:ok, n: n, zona: "zona#{n}", categoria: "agua#{n}"}
  end

  test "resumen reúne recursos, necesidades, personas, mensajes, mascotas y albergues", ctx do
    {:ok, _} = Zonas.registrar(ctx.zona, "Zona", :alto, 10)
    {:ok, _} = Inventario.registrar("R#{ctx.n}", "Agua", ctx.categoria, 50, "litros", "centro#{ctx.n}")
    {:ok, _} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "ana")
    {:ok, _} = Personas.reportar("#{ctx.n}", "Andrés", ctx.zona, :localizada)
    {:ok, _} = Personas.enviar_mensaje("ana", "#{ctx.n}", "Hola")
    {:ok, _} = Mascotas.reportar("lost", "perro", "Luna", "negra", "mediana", ctx.zona, "300")
    {:ok, _} = Albergues.registrar("A#{ctx.n}", "Norte", ctx.zona, 10)

    resumen = Reportes.resumen()
    assert resumen.zonas >= 1
    assert resumen.recursos[{ctx.categoria, "litros"}] == 50
    assert resumen.necesidades.pendientes >= 1
    assert resumen.personas.localizadas >= 1
    assert resumen.mensajes.pendientes >= 1
    assert resumen.mascotas.perdidas >= 1
    assert resumen.albergues.total >= 1
  end

  test "texto_resumen muestra las secciones principales", ctx do
    {:ok, _} = Inventario.registrar("R#{ctx.n}", "Agua", ctx.categoria, 7, "litros", "centro#{ctx.n}")
    texto = Reportes.texto_resumen()

    for seccion <- ["Resumen general", "Recursos restantes", "Necesidades:", "Personas:", "Mensajes:", "Mascotas:", "Albergues:"] do
      assert texto =~ seccion
    end

    assert texto =~ "#{ctx.categoria}: 7 litros"
  end

  test "recursos críticos lista los que tienen pocas existencias", ctx do
    {:ok, _} = Inventario.registrar("R#{ctx.n}", "Agua", ctx.categoria, 3, "litros", "centro#{ctx.n}")
    assert Reportes.texto_recursos_criticos(5) =~ "R#{ctx.n}"
    refute Reportes.texto_recursos_criticos(2) =~ "R#{ctx.n}"
  end

  test "las pendientes salen de la más crítica a la menos crítica", ctx do
    {:ok, baja} = Necesidades.registrar(:agua, 5, :baja, ctx.zona, "", "ana")
    {:ok, critica} = Necesidades.registrar(:agua, 5, :critica, ctx.zona, "", "ana")
    texto = Reportes.texto_pendientes()
    {pos_critica, _} = :binary.match(texto, critica.id)
    {pos_baja, _} = :binary.match(texto, baja.id)
    assert pos_critica < pos_baja
  end

  test "lista devuelve el mensaje vacío o las líneas" do
    assert Reportes.lista([], &to_string/1, "nada") == "nada"
    assert Reportes.lista([1, 2], &to_string/1, "nada") == "1\n2"
  end

  test "las líneas de cada entidad contienen sus datos principales" do
    {:ok, n} = Necesidad.nuevo("N001", :agua, 30, :critica, "centro", "Punto 3", "laura")
    assert Reportes.linea_necesidad(n) =~ "N001 [critica] agua x30"
    {:ok, r} = Recurso.nuevo("R001", "Agua", "agua", 200, "litros", "centro_1")
    assert Reportes.linea_recurso(r) =~ "200 litros en centro_1"
    {:ok, a} = Albergue.nuevo("A01", "Norte", "z", 150)
    assert Reportes.linea_albergue(Albergue.resumen(a)) =~ "0/150"
  end
end
