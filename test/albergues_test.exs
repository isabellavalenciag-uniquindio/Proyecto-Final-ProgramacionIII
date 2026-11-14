defmodule AlberguesTest do
  use ExUnit.Case

  setup do
    a = "A#{System.unique_integer([:positive])}"
    {:ok, _} = Zonas.registrar(a <> "_zona", "Zona de prueba", :alto)
    {:ok, a: a}
  end

  test "registra y consulta cupos", %{a: a} do
    assert {:ok, %{capacidad: 5, cupos: 5}} = Albergues.registrar(a, "Norte", a <> "_zona", 5)
    assert {:error, :duplicado} = Albergues.registrar(a, "Otro", a <> "_zona", 5)
    assert {:error, :no_existe} = Albergues.consultar("no_existe")
  end

  test "los ingresos simultáneos de una persona en dos albergues aceptan solo uno", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 2)
    {:ok, _} = Albergues.registrar(a <> "sur", "Sur", a <> "_zona", 2)
    documento = a <> "persona"
    resultados = [a, a <> "sur"]
      |> Enum.map(fn codigo -> Task.async(fn -> Albergues.ingresar(codigo, documento) end) end)
      |> Task.await_many()
    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert Enum.count(resultados, &(&1 == {:error, :en_otro_albergue})) == 1
    {:ok, primero} = Albergues.consultar(a)
    {:ok, segundo} = Albergues.consultar(a <> "sur")
    assert primero.ocupacion + segundo.ocupacion == 1
    ocupado = if primero.ocupacion == 1, do: a, else: a <> "sur"
    libre = if ocupado == a, do: a <> "sur", else: a
    assert {:ok, _} = Albergues.salir(ocupado, documento)
    assert {:ok, _} = Albergues.ingresar(libre, documento)
  end

  test "un ingreso con transición inválida no ocupa cupo", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 2)
    {:ok, _} = Personas.reportar(a, "Ana", a <> "_zona", :reunificada)
    assert {:error, :ya_cerrada} = Albergues.ingresar(a, a)
    assert {:ok, %{ocupacion: 0}} = Albergues.consultar(a)
    assert {:ok, %{estado: :reunificada}} = Personas.obtener(a)
  end

  test "rechaza capacidad no positiva", %{a: a} do
    assert {:error, :cantidad_invalida} = Albergues.registrar(a, "Norte", a <> "_zona", 0)
    assert {:error, :cantidad_invalida} = Albergues.registrar(a, "Norte", a <> "_zona", -3)
  end

  test "nunca supera la capacidad", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 2)
    assert {:ok, %{ocupacion: 1}} = Albergues.ingresar(a, "#{a}-111")
    assert {:ok, %{ocupacion: 2, cupos: 0}} = Albergues.ingresar(a, "#{a}-222")
    assert {:error, :sin_cupo} = Albergues.ingresar(a, "#{a}-333")
  end

  test "no permite ingresar dos veces a la misma persona", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 5)
    {:ok, _} = Albergues.ingresar(a, "#{a}-111")
    assert {:error, :ya_registrado} = Albergues.ingresar(a, "#{a}-111")
  end

  test "la salida libera el cupo", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 1)
    {:ok, _} = Albergues.ingresar(a, "#{a}-111")
    assert {:ok, %{cupos: 1}} = Albergues.salir(a, "#{a}-111")
    assert {:error, :no_esta} = Albergues.salir(a, "#{a}-111")
  end

  test "20 ingresos simultáneos a un albergue de 10: se aceptan exactamente 10", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 10)

    resultados =
      1..20
      |> Enum.map(fn i -> Task.async(fn -> Albergues.ingresar(a, "#{a}-doc#{i}") end) end)
      |> Task.await_many()

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
    assert Enum.count(resultados, &match?({:error, :sin_cupo}, &1)) == 10
    assert {:ok, %{ocupacion: 10}} = Albergues.consultar(a)
  end

  test "asocia recursos y necesidades sin repetir", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 5)
    recurso = a <> "R"
    {:ok, _} = Inventario.registrar(recurso, "Agua", "agua", 5, "litros", a)
    {:ok, n} = Necesidades.registrar(:agua, 5, :alta, a <> "_zona", "", "ana")
    {:ok, _} = Albergues.asociar_recurso(a, recurso)
    {:ok, _} = Albergues.asociar_recurso(a, recurso)
    {:ok, _} = Albergues.asociar_necesidad(a, n.id)
    assert {:ok, %{recursos: [^recurso], necesidades: [id]}} = Albergues.consultar(a)
    assert id == n.id
  end

  test "el ranking ordena por ocupación", %{a: a} do
    {:ok, _} = Albergues.registrar(a <> "x", "Lleno", a <> "_zona", 2)
    {:ok, _} = Albergues.registrar(a <> "y", "Vacío", a <> "_zona", 2)
    {:ok, _} = Albergues.ingresar(a <> "x", "#{a}-1")
    {:ok, _} = Albergues.ingresar(a <> "x", "#{a}-2")

    codigos = Albergues.ranking(1000) |> Enum.map(& &1.codigo)
    assert Enum.find_index(codigos, &(&1 == a <> "x")) < Enum.find_index(codigos, &(&1 == a <> "y"))
  end

  test "si el proceso de un albergue cae, el supervisor lo reinicia", %{a: a} do
    {:ok, _} = Albergues.registrar(a, "Norte", a <> "_zona", 5)
    [{pid, _}] = Registry.lookup(Emergencias.RegistroAlbergues, a)
    Process.exit(pid, :kill)
    Process.sleep(100)
    assert {:ok, %{codigo: ^a}} = Albergues.consultar(a)
  end
end
