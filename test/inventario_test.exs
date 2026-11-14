defmodule InventarioTest do
  use ExUnit.Case

  # Cada prueba usa nombres únicos: el proceso Inventario es compartido
  setup do
    n = System.unique_integer([:positive])
    {:ok, categoria: "agua#{n}", codigo: "R#{n}", ubicacion: "centro#{n}"}
  end

  defp registrar(ctx, cantidad) do
    {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, cantidad, "litros", ctx.ubicacion)
  end

  describe "registrar/6" do
    test "consulta recursos por zona y conserva la zona al transferir", ctx do
      norte = "norte_#{ctx.codigo}"
      sur = "sur_#{ctx.codigo}"
      {:ok, _} = Zonas.registrar(norte, "Norte", :alto)
      {:ok, _} = Zonas.registrar(sur, "Sur", :alto)
      {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 50, "litros", ctx.ubicacion, norte)
      assert Inventario.disponibilidad(ctx.codigo, nil, norte) == 50
      assert Inventario.listar(codigo: ctx.codigo, zona: sur) == []
      assert {:ok, %{destino: %{zona: ^sur}}} =
               Inventario.transferir(ctx.codigo, ctx.ubicacion, ctx.ubicacion <> "sur", 20, sur)
      assert Inventario.disponibilidad(ctx.codigo, nil, norte) == 30
      assert Inventario.disponibilidad(ctx.codigo, nil, sur) == 20
      assert {:error, :zona_destino_distinta} =
               Inventario.transferir(ctx.codigo, ctx.ubicacion, ctx.ubicacion <> "sur", 1, norte)
      assert Inventario.disponibilidad(ctx.codigo, nil, norte) == 30
    end

    test "rechaza una zona inexistente antes de guardar", ctx do
      assert {:error, {:zona_inexistente, _}} =
               Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 5, "litros", ctx.ubicacion, "fantasma")
      assert {:error, :no_existe} = Inventario.obtener(ctx.codigo, ctx.ubicacion)
    end

    test "el CSV conserva la zona y admite recursos anteriores sin zona", ctx do
      {:ok, r} = Recurso.nuevo(ctx.codigo, "Agua", ctx.categoria, 5, "litros", ctx.ubicacion, "norte")
      fila = Recurso.a_fila(r)
      assert Recurso.desde_fila(fila) == r
      assert %{zona: nil} = Recurso.desde_fila(Enum.take(fila, 7))
    end

    test "crea un recurso", ctx do
      assert {:ok, %Recurso{cantidad: 50}} =
               Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 50, "litros", ctx.ubicacion)
    end

    test "no permite repetir código en el mismo lugar", ctx do
      registrar(ctx, 10)
      assert {:error, :duplicado} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 5, "litros", ctx.ubicacion)
    end

    test "rechaza cantidades negativas", ctx do
      assert {:error, :cantidad_invalida} =
               Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, -5, "litros", ctx.ubicacion)
    end
  end

  describe "entradas y salidas" do
    test "la salida no deja el inventario en negativo", ctx do
      registrar(ctx, 10)
      assert {:error, :insuficiente} = Inventario.salida(ctx.codigo, ctx.ubicacion, 11)
      assert {:ok, %Recurso{cantidad: 4}} = Inventario.salida(ctx.codigo, ctx.ubicacion, 6)
    end

    test "conserva el historial de movimientos", ctx do
      registrar(ctx, 10)
      {:ok, recurso} = Inventario.entrada(ctx.codigo, ctx.ubicacion, 5)
      assert [{:entrada, 5, _fecha}, {:alta, 10, _}] = recurso.movimientos
    end

    test "rechaza un recurso que no existe", ctx do
      assert {:error, :no_existe} = Inventario.entrada("nada", ctx.ubicacion, 5)
    end
  end

  describe "reservar/2" do
    test "reserva por categoría y descuenta", ctx do
      registrar(ctx, 50)
      codigo = ctx.codigo
      ubicacion = ctx.ubicacion
      assert {:ok, [{^codigo, ^ubicacion, 30}]} = Inventario.reservar(ctx.categoria, 30)
      assert Inventario.disponibilidad(ctx.categoria) == 20
    end

    test "no reserva más de lo disponible y no cambia nada", ctx do
      registrar(ctx, 50)
      assert {:error, :insuficiente} = Inventario.reservar(ctx.categoria, 51)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "toma de varios lugares cuando hace falta", ctx do
      registrar(ctx, 20)
      {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 20, "litros", ctx.ubicacion <> "b")
      assert {:ok, detalle} = Inventario.reservar(ctx.categoria, 30)
      assert length(detalle) == 2
      assert detalle |> Enum.map(fn {_, _, n} -> n end) |> Enum.sum() == 30
    end

    test "liberar devuelve las unidades", ctx do
      registrar(ctx, 50)
      {:ok, detalle} = Inventario.reservar(ctx.categoria, 30)
      assert :ok = Inventario.liberar(detalle)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end
  end

  describe "conflicto concurrente" do
    test "50 L con solicitudes simultáneas de 30 y 25: solo una se confirma", ctx do
      registrar(ctx, 50)

      resultados =
        [30, 25]
        |> Enum.map(fn n -> Task.async(fn -> Inventario.reservar(ctx.categoria, n) end) end)
        |> Task.await_many()

      oks = Enum.filter(resultados, &match?({:ok, _}, &1))
      errores = Enum.filter(resultados, &match?({:error, :insuficiente}, &1))
      assert length(oks) == 1
      assert length(errores) == 1

      reservado = oks |> Enum.flat_map(fn {:ok, d} -> d end) |> Enum.map(fn {_, _, n} -> n end) |> Enum.sum()
      assert reservado <= 50
      assert Inventario.disponibilidad(ctx.categoria) == 50 - reservado
    end

    test "100 reservas de 1 unidad sobre 50: exactamente 50 se confirman", ctx do
      registrar(ctx, 50)

      resultados =
        1..100
        |> Enum.map(fn _ -> Task.async(fn -> Inventario.reservar(ctx.categoria, 1) end) end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 50
      assert Enum.count(resultados, &match?({:error, :insuficiente}, &1)) == 50
      assert Inventario.disponibilidad(ctx.categoria) == 0
    end
  end

  describe "transferir/4" do
    test "mueve unidades y crea el recurso en el destino", ctx do
      registrar(ctx, 100)
      assert {:ok, %{origen: o, destino: d}} = Inventario.transferir(ctx.codigo, ctx.ubicacion, "albergue_x", 30)
      assert o.cantidad == 70
      assert d.cantidad == 30
      assert Inventario.disponibilidad(ctx.categoria) == 100
    end

    test "no transfiere más de lo que hay", ctx do
      registrar(ctx, 10)
      assert {:error, :insuficiente} = Inventario.transferir(ctx.codigo, ctx.ubicacion, "otro", 11)
    end

    test "no transfiere al mismo lugar", ctx do
      registrar(ctx, 10)
      assert {:error, :mismo_lugar} = Inventario.transferir(ctx.codigo, ctx.ubicacion, ctx.ubicacion, 1)
    end

    test "rechaza el mismo lugar aunque tenga espacios y conserva las existencias", ctx do
      registrar(ctx, 50)

      assert {:error, :mismo_lugar} =
               Inventario.transferir(ctx.codigo, ctx.ubicacion, " #{ctx.ubicacion} ", 10)

      assert {:ok, %Recurso{cantidad: 50}} = Inventario.obtener(ctx.codigo, ctx.ubicacion)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "normaliza el destino antes de buscarlo para no sobrescribir sus existencias", ctx do
      registrar(ctx, 50)
      destino = ctx.ubicacion <> "_destino"
      {:ok, _} = Inventario.registrar(ctx.codigo, "Agua", ctx.categoria, 100, "litros", destino)

      assert {:ok, %{origen: origen, destino: recibido}} =
               Inventario.transferir(" #{ctx.codigo} ", " #{ctx.ubicacion} ", " #{destino} ", 10)

      assert origen.cantidad == 40
      assert recibido.cantidad == 110
      assert Inventario.disponibilidad(ctx.categoria) == 150
    end

    test "un destino vacío no descuenta existencias", ctx do
      registrar(ctx, 50)
      assert {:error, :texto_vacio} = Inventario.transferir(ctx.codigo, ctx.ubicacion, "  ", 10)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end
  end

  test "criticos/1 lista los recursos con pocas existencias", ctx do
    registrar(ctx, 3)
    assert Enum.any?(Inventario.criticos(5), &(&1.codigo == ctx.codigo))
  end
end
