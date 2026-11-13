defmodule MascotasTest do
  use ExUnit.Case

  defp mascota(id, tipo, especie, nombre, color, tamano, zona, carac \\ "") do
    {:ok, m} = Mascota.nuevo(id, tipo, especie, nombre, color, tamano, zona, "300", carac)
    m
  end

  describe "Mascota.nuevo/9" do
    test "acepta lost/found y tamaños en femenino" do
      assert %Mascota{tipo: :perdida, tamano: :mediano} = mascota("M1", "lost", "perro", "Luna", "negra", "mediana", "z")
      assert %Mascota{tipo: :encontrada, tamano: :pequeno} = mascota("M2", "found", "perro", "", "negra", "pequeña", "z")
    end

    test "el nombre vacío queda como desconocido" do
      assert %Mascota{nombre: "desconocido"} = mascota("M1", :encontrada, "perro", "  ", "negra", :mediano, "z")
    end

    test "valida los datos" do
      assert {:error, :tipo_invalido} = Mascota.nuevo("M1", "rara", "perro", "L", "negra", "mediana", "z", "1")
      assert {:error, :tamano_invalido} = Mascota.nuevo("M1", :perdida, "perro", "L", "negra", "enorme", "z", "1")
      assert {:error, :texto_vacio} = Mascota.nuevo("M1", :perdida, "", "L", "negra", "mediana", "z", "1")
    end
  end

  describe "similitud/2" do
    test "mismos datos principales dan 85 puntos" do
      a = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte")
      b = mascota("M2", :encontrada, "perro", "", "negra", "mediana", "norte")
      assert Mascota.similitud(a, b) == 85
    end

    test "con nombre y características iguales llega a 100" do
      a = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte", "collar rojo")
      b = mascota("M2", :encontrada, "perro", "luna", "Negra", "mediana", "norte", "collar rojo")
      assert Mascota.similitud(a, b) == 100
    end

    test "especie distinta da 0" do
      a = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte")
      b = mascota("M2", :encontrada, "gato", "Luna", "negra", "mediana", "norte")
      assert Mascota.similitud(a, b) == 0
    end

    test "un tamaño contiguo da la mitad del peso y uno lejano nada" do
      mediana = mascota("M1", :perdida, "perro", "", "negra", "mediana", "norte")
      pequena = mascota("M2", :perdida, "perro", "", "negra", "pequeño", "norte")
      grande = mascota("M3", :encontrada, "perro", "", "negra", "grande", "norte")
      assert Mascota.similitud(mediana, grande) == 78
      assert Mascota.similitud(pequena, grande) == 70
    end

    test "es simétrica" do
      a = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte", "manchas blancas")
      b = mascota("M2", :encontrada, "perro", "Luna", "café", "grande", "sur", "manchas blancas")
      assert Mascota.similitud(a, b) == Mascota.similitud(b, a)
    end
  end

  describe "coincidencias" do
    test "solo devuelve pares perdida-encontrada desde el umbral, de mayor a menor" do
      perdida = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte")
      buena = mascota("M2", :encontrada, "perro", "", "negra", "mediana", "norte")
      regular = mascota("M3", :encontrada, "perro", "", "negra", "pequeño", "norte")
      mala = mascota("M4", :encontrada, "perro", "", "blanca", "grande", "sur")

      pares = Mascota.coincidencias([perdida, buena, regular, mala])
      assert Enum.map(pares, & &1.encontrada) == ["M2", "M3"]
      assert hd(pares).puntaje == 85
    end

    test "ignora los reportes resueltos" do
      perdida = %{mascota("M1", :perdida, "perro", "", "negra", "mediana", "n") | estado: :resuelta}
      encontrada = mascota("M2", :encontrada, "perro", "", "negra", "mediana", "n")
      assert Mascota.coincidencias([perdida, encontrada]) == []
    end

    test "la versión paralela da el mismo resultado que la secuencial" do
      colores = ["negra", "blanca", "café"]
      zonas = ["norte", "sur"]

      lista =
        for i <- 1..40 do
          tipo = if rem(i, 2) == 0, do: :perdida, else: :encontrada
          mascota("M#{i}", tipo, "perro", "", Enum.at(colores, rem(i, 3)), "mediana", Enum.at(zonas, rem(i, 2)))
        end

      assert Mascota.coincidencias(lista, 0) == Mascota.coincidencias_paralelo(lista, 0)
    end

    test "ida y vuelta al CSV" do
      m = mascota("M1", :perdida, "perro", "Luna", "negra", "mediana", "norte", "collar rojo")
      assert m |> Mascota.a_fila() |> Mascota.desde_fila() == m
    end
  end

  describe "Mascotas (proceso)" do
    setup do
      n = System.unique_integer([:positive])
      {:ok, especie: "especie#{n}", zona: "zona#{n}"}
    end

    test "registra reportes con identificador generado y los consulta", ctx do
      {:ok, m} = Mascotas.reportar("lost", ctx.especie, "Luna", "negra", "mediana", ctx.zona, "300")
      assert String.starts_with?(m.id, "M")
      assert [%Mascota{id: id}] = Mascotas.listar(especie: ctx.especie, zona: ctx.zona, estado: :activa)
      assert id == m.id
    end

    test "match marca posible coincidencia y confirmar cierra ambos reportes", ctx do
      {:ok, p} = Mascotas.reportar("lost", ctx.especie, "Luna", "negra", "mediana", ctx.zona, "300")
      {:ok, e} = Mascotas.reportar("found", ctx.especie, "", "negra", "mediana", ctx.zona, "301")

      assert Enum.any?(Mascotas.coincidencias(), &(&1.perdida == p.id and &1.encontrada == e.id))
      assert {:ok, %Mascota{estado: :posible_coincidencia}} = Mascotas.obtener(p.id)

      assert {:ok, %{perdida: pc, encontrada: ec}} = Mascotas.confirmar(p.id, e.id)
      assert pc.estado == :resuelta and ec.estado == :resuelta
      assert pc.coincidencia == e.id and ec.coincidencia == p.id
    end

    test "no se confirma dos veces ni con especies distintas ni con dos perdidas", ctx do
      {:ok, p} = Mascotas.reportar("lost", ctx.especie, "Luna", "negra", "mediana", ctx.zona, "300")
      {:ok, e} = Mascotas.reportar("found", ctx.especie, "", "negra", "mediana", ctx.zona, "301")
      {:ok, otra} = Mascotas.reportar("lost", ctx.especie, "Rex", "negra", "mediana", ctx.zona, "302")
      {:ok, gato} = Mascotas.reportar("found", ctx.especie <> "g", "", "negra", "mediana", ctx.zona, "303")

      assert {:error, :par_invalido} = Mascotas.confirmar(p.id, otra.id)
      assert {:error, :especie_distinta} = Mascotas.confirmar(p.id, gato.id)
      assert {:error, :no_existe} = Mascotas.confirmar(p.id, "M999999")

      # Se aceptan en cualquier orden
      assert {:ok, _} = Mascotas.confirmar(e.id, p.id)
      assert {:error, :ya_resuelta} = Mascotas.confirmar(p.id, e.id)
    end

    test "dos confirmaciones simultáneas: solo una se acepta", ctx do
      {:ok, p} = Mascotas.reportar("lost", ctx.especie, "Luna", "negra", "mediana", ctx.zona, "300")
      {:ok, e} = Mascotas.reportar("found", ctx.especie, "", "negra", "mediana", ctx.zona, "301")

      resultados =
        1..2
        |> Enum.map(fn _ -> Task.async(fn -> Mascotas.confirmar(p.id, e.id) end) end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &match?({:error, :ya_resuelta}, &1)) == 1
    end
  end
end
