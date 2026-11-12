defmodule PersistenciaTest do
  use ExUnit.Case

  setup do
    ruta = Path.join(System.tmp_dir!(), "emergencias_#{System.unique_integer([:positive])}.csv")
    on_exit(fn -> File.rm(ruta) end)
    {:ok, ruta: ruta}
  end

  describe "Archivo" do
    test "escribe y lee filas", %{ruta: ruta} do
      filas = [["a", "1", "x;y"], ["b", "", "z"]]
      assert :ok = Archivo.escribir_en(ruta, filas)
      assert Archivo.leer_en(ruta) == filas
    end

    test "un archivo que no existe se lee como lista vacía" do
      assert Archivo.leer_en("/tmp/no_existe_#{System.unique_integer([:positive])}.csv") == []
    end

    test "upsert reemplaza por clave o agrega" do
      assert Archivo.upsert([["a", "1"], ["b", "2"]], ["b", "9"]) == [["a", "1"], ["b", "9"]]
      assert Archivo.upsert([["a", "1"]], ["c", "3"]) == [["a", "1"], ["c", "3"]]
    end

    test "sanear quita los caracteres que rompen el formato" do
      assert Archivo.sanear("a|b\nc") == "a b c"
      assert Archivo.sanear_item("a;b:c") == "a-b-c"
    end

    test "las listas ida y vuelta" do
      assert Archivo.texto_a_lista(Archivo.lista_a_texto(["a", "b"])) == ["a", "b"]
      assert Archivo.texto_a_lista("") == []
    end
  end

  describe "ida y vuelta de las entidades" do
    test "Recurso", %{ruta: ruta} do
      {:ok, r} = Recurso.nuevo("R001", "Agua", "agua", 200, "litros", "centro_1")
      {:ok, r} = Recurso.restar(r, 30, :reserva)
      :ok = Archivo.escribir_en(ruta, [Recurso.a_fila(r)])
      assert [fila] = Archivo.leer_en(ruta)
      assert Recurso.desde_fila(fila) == r
    end

    test "Necesidad" do
      {:ok, n} = Necesidad.nuevo("N001", :agua, 30, :critica, "centro", "Punto 3", "laura")
      {:ok, n} = Necesidad.asignar(n, [{"R001", "centro_1", 10}, {"R002", "centro_2", 5}])
      assert n |> Necesidad.a_fila() |> Necesidad.desde_fila() == n
    end

    test "Albergue" do
      {:ok, a} = Albergue.nuevo("A01", "Norte", "zona_norte", 10)
      {:ok, a} = Albergue.ingresar(a, "111")
      {:ok, a} = Albergue.asociar(a, :recurso, "R001")
      assert a |> Albergue.a_fila() |> Albergue.desde_fila() == a
    end
  end

  describe "Persistencia (proceso)" do
    test "con la persistencia desactivada no escribe ni falla" do
      assert [] = Persistencia.cargar(:inexistente)
      assert :ok = Persistencia.guardar(:inexistente, [["a"]])
      assert :ok = Persistencia.sincronizar()
    end
  end
end
