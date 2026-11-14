defmodule NecesidadesTest do
  use ExUnit.Case

  setup do
    n = System.unique_integer([:positive])
    {:ok, zona: "zona#{n}", categoria: "agua#{n}", ubicacion: "centro#{n}", codigo: "R#{n}"}
  end

  defp stock(ctx, cantidad) do
    {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, cantidad, "litros", ctx.ubicacion)
  end

  describe "Necesidad (reglas puras)" do
    test "no permite avanzar con recursos faltantes, incluso en estados recuperados" do
      {:ok, n} = Necesidad.nuevo("N001", :agua, 10, :alta, "z", "", "ana")
      assert {:error, :recursos_incompletos} = Necesidad.cambiar_estado(n, :asignada)
      {:ok, parcial} = Necesidad.asignar(n, [{"R1", "bodega", 5}])
      assert {:error, :recursos_incompletos} = Necesidad.cambiar_estado(parcial, :asignada)
      assert {:error, :recursos_incompletos} =
               Necesidad.cambiar_estado(%{parcial | estado: :asignada}, :en_atencion)
      assert {:error, :recursos_incompletos} =
               Necesidad.cambiar_estado(%{parcial | estado: :en_atencion}, :atendida)
      assert {:ok, %{estado: :cancelada}} = Necesidad.cambiar_estado(parcial, :cancelada)
    end

    test "una reserva completa permite avanzar hasta atendida" do
      {:ok, n} = Necesidad.nuevo("N001", :agua, 10, :alta, "z", "", "ana")
      {:ok, n} = Necesidad.asignar(n, [{"R1", "bodega", 10}])
      assert {:ok, n} = Necesidad.cambiar_estado(n, :en_atencion)
      assert {:ok, %{estado: :atendida}} = Necesidad.cambiar_estado(n, :atendida)
    end

    test "valida los datos" do
      assert {:error, :tipo_invalido} = Necesidad.nuevo("N001", :xyz, 5, :alta, "z", "", "ana")
      assert {:error, :prioridad_invalida} = Necesidad.nuevo("N001", :agua, 5, :urgente, "z", "", "ana")
      assert {:error, :cantidad_invalida} = Necesidad.nuevo("N001", :agua, -5, :alta, "z", "", "ana")
    end

    test "acepta texto con tildes y mayúsculas" do
      assert {:ok, %Necesidad{prioridad: :critica, tipo: :primeros_auxilios}} =
               Necesidad.nuevo("N001", "Primeros Auxilios", 5, "Crítica", "z", "", "ana")
    end

    test "solo permite transiciones válidas" do
      {:ok, n} = Necesidad.nuevo("N001", :agua, 5, :alta, "z", "", "ana")
      assert {:error, :transicion_invalida} = Necesidad.cambiar_estado(n, :atendida)
      assert {:ok, n} = Necesidad.cambiar_estado(n, :cancelada)
      assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(n, :cancelada)
      assert {:error, :ya_cerrada} = Necesidad.cambiar_estado(n, :atendida)
    end

    test "insertar_ordenado ordena por prioridad y luego por antigüedad" do
      {:ok, baja} = Necesidad.nuevo("N001", :agua, 5, :baja, "z", "", "ana")
      {:ok, critica} = Necesidad.nuevo("N002", :agua, 5, :critica, "z", "", "ana")
      {:ok, alta} = Necesidad.nuevo("N003", :agua, 5, :alta, "z", "", "ana")
      {:ok, critica2} = Necesidad.nuevo("N004", :agua, 5, :critica, "z", "", "ana")

      lista =
        []
        |> Necesidad.insertar_ordenado(baja)
        |> Necesidad.insertar_ordenado(critica)
        |> Necesidad.insertar_ordenado(alta)
        |> Necesidad.insertar_ordenado(critica2)

      assert Enum.map(lista, & &1.id) == ["N002", "N004", "N003", "N001"]
    end
  end

  describe "Necesidades (proceso)" do
    test "rechaza medicamentos para agua sin descontar ni completar la solicitud", ctx do
      {:ok, _} = Inventario.registrar(ctx.codigo, "Medicamentos", "medicamentos", 20, "cajas", ctx.ubicacion)
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "ana")
      assert {:error, :recurso_incompatible} = Necesidades.asignar(n.id, ctx.codigo, 10)
      assert {:ok, ^n} = Necesidades.obtener(n.id)
      assert Inventario.disponibilidad(ctx.codigo) == 20
    end

    test "una categoría conocida prevalece sobre un nombre contradictorio", ctx do
      {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", "medicamentos", 20, "cajas", ctx.ubicacion)
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "ana")
      assert {:error, :recurso_incompatible} = Necesidades.asignar(n.id, ctx.codigo, 10)
      assert Inventario.disponibilidad(ctx.codigo) == 20
    end

    test "una reserva por categoría no mezcla recursos incompatibles", ctx do
      stock(ctx, 5)
      {:ok, _} = Inventario.registrar(ctx.codigo <> "M", "Medicamentos", ctx.categoria, 20, "cajas", ctx.ubicacion)
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "ana")
      assert {:error, :insuficiente} = Necesidades.asignar(n.id, ctx.categoria, 10)
      assert Inventario.disponibilidad(ctx.categoria) == 25
      assert {:ok, %{estado: :pendiente}} = Necesidades.asignar(n.id, ctx.categoria, 5)
      assert Inventario.disponibilidad(ctx.categoria) == 20
    end

    test "un cambio manual no completa una necesidad ni modifica sus reservas", ctx do
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "ana")
      assert {:error, :recursos_incompletos} = Necesidades.cambiar_estado(n.id, :asignada)
      assert {:ok, ^n} = Necesidades.obtener(n.id)
    end

    test "registra y lista ordenado por prioridad", ctx do
      {:ok, baja} = Necesidades.registrar(:agua, 5, :baja, ctx.zona, "", "ana")
      {:ok, critica} = Necesidades.registrar(:agua, 5, :critica, ctx.zona, "", "ana")
      assert Enum.map(Necesidades.listar(zona: ctx.zona), & &1.id) == [critica.id, baja.id]
      assert Necesidades.listar(zona: ctx.zona, prioridad: "critica") |> length() == 1
    end

    test "asignar descuenta del inventario y completa la necesidad", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 30, :critica, ctx.zona, "Punto 3", "laura")
      assert {:ok, %Necesidad{estado: :asignada}} = Necesidades.asignar(n.id, ctx.categoria, 30)
      assert Inventario.disponibilidad(ctx.categoria) == 20
    end

    test "una asignación parcial deja la necesidad pendiente", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", "laura")
      assert {:ok, %Necesidad{estado: :pendiente} = parcial} = Necesidades.asignar(n.id, ctx.categoria, 20)
      assert Necesidad.faltante(parcial) == 10
      assert {:error, :excede_requerida} = Necesidades.asignar(n.id, ctx.categoria, 15)
      assert Inventario.disponibilidad(ctx.categoria) == 30
    end

    test "no asigna más de lo disponible", ctx do
      stock(ctx, 10)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", "laura")
      assert {:error, :insuficiente} = Necesidades.asignar(n.id, ctx.categoria, 30)
    end

    test "una necesidad atendida no vuelve a consumir recursos", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "laura")
      {:ok, _} = Necesidades.asignar(n.id, ctx.categoria, 10)
      {:ok, _} = Necesidades.cambiar_estado(n.id, :en_atencion)
      {:ok, _} = Necesidades.cambiar_estado(n.id, :atendida)

      assert {:error, :estado_invalido} = Necesidades.asignar(n.id, ctx.categoria, 5)
      assert Inventario.disponibilidad(ctx.categoria) == 40
    end

    test "no se cierra dos veces", ctx do
      {:ok, n} = Necesidades.registrar(:agua, 10, :alta, ctx.zona, "", "laura")
      assert {:ok, _} = Necesidades.cancelar(n.id)
      assert {:error, :ya_cerrada} = Necesidades.cancelar(n.id)
    end

    test "cancelar devuelve lo asignado al inventario", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", "laura")
      {:ok, _} = Necesidades.asignar(n.id, ctx.categoria, 30)
      assert Inventario.disponibilidad(ctx.categoria) == 20
      {:ok, _} = Necesidades.cancelar(n.id)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "cambiar_estado devuelve una reserva parcial al cancelar con texto", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", "laura")
      {:ok, _} = Necesidades.asignar(n.id, ctx.categoria, 10)

      assert {:ok, %Necesidad{estado: :cancelada}} = Necesidades.cambiar_estado(n.id, "Cancelada")
      assert Inventario.disponibilidad(ctx.categoria) == 50
      assert {:error, :ya_cerrada} = Necesidades.cancelar(n.id)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "cancelaciones simultáneas por ambas vías devuelven los recursos una sola vez", ctx do
      stock(ctx, 50)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", "laura")
      {:ok, _} = Necesidades.asignar(n.id, ctx.categoria, 30)

      resultados =
        [fn -> Necesidades.cancelar(n.id) end, fn -> Necesidades.cambiar_estado(n.id, :cancelada) end]
        |> Enum.map(&Task.async/1)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &match?({:error, :ya_cerrada}, &1)) == 1
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "dos necesidades compiten por 50 L (30 y 25): solo una se asigna", ctx do
      stock(ctx, 50)
      {:ok, a} = Necesidades.registrar(:agua, 30, :critica, ctx.zona, "", "laura")
      {:ok, b} = Necesidades.registrar(:agua, 25, :alta, ctx.zona, "", "pedro")

      resultados =
        [{a.id, 30}, {b.id, 25}]
        |> Enum.map(fn {id, n} -> Task.async(fn -> Necesidades.asignar(id, ctx.categoria, n) end) end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &match?({:error, :insuficiente}, &1)) == 1
      assert Inventario.disponibilidad(ctx.categoria) in [20, 25]
    end
  end
end
