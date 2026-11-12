defmodule ZonasTest do
  use ExUnit.Case

  defp arbol do
    {:ok, zona} = Zona.nueva("z1", "Centro", :alto, 100)
    {:ok, s1} = Zona.nuevo_sector("s1", "Sector 1", :critico, 40)
    {:ok, s2} = Zona.nuevo_sector("s2", "Sector 2", :medio, 10)
    {:ok, p1} = Zona.nuevo_punto("p1", "Punto 1", :critico, 5)
    {:ok, zona} = Zona.agregar(zona, "z1", s1)
    {:ok, zona} = Zona.agregar(zona, "z1", s2)
    {:ok, zona} = Zona.agregar(zona, "s1", p1)
    zona
  end

  describe "Zona (árbol recursivo)" do
    test "buscar encuentra nodos a cualquier profundidad" do
      assert {:ok, %Zona{nombre: "Punto 1", tipo: :punto}} = Zona.buscar(arbol(), "p1")
      assert {:error, :no_existe} = Zona.buscar(arbol(), "xx")
    end

    test "estadisticas acumula zona, sectores y puntos" do
      assert %{afectados: 155, sectores: 2, puntos: 1} = Zona.estadisticas(arbol())
      {:ok, sector} = Zona.buscar(arbol(), "s1")
      assert %{afectados: 45, sectores: 1, puntos: 1} = Zona.estadisticas(sector)
    end

    test "acumulado suma todo el árbol" do
      assert Zona.acumulado(arbol()) == 155
    end

    test "por_nivel lista los nodos con ese nivel" do
      assert arbol() |> Zona.por_nivel(:critico) |> Enum.map(& &1.codigo) == ["s1", "p1"]
    end

    test "respeta la jerarquía y no repite códigos" do
      {:ok, punto} = Zona.nuevo_punto("p9", "P", :bajo, 0)
      assert {:error, :jerarquia_invalida} = Zona.agregar(arbol(), "z1", punto)
      {:ok, repetido} = Zona.nuevo_sector("s1", "Otro", :bajo, 0)
      assert {:error, :codigo_duplicado} = Zona.agregar(arbol(), "z1", repetido)
      assert {:error, :padre_no_existe} = Zona.agregar(arbol(), "nada", repetido)
    end

    test "valida nivel y cantidades" do
      assert {:error, :nivel_invalido} = Zona.nueva("z", "Z", :enorme, 0)
      assert {:error, :cantidad_invalida} = Zona.nueva("z", "Z", :alto, -1)
    end

    test "aplana y reconstruye el árbol sin perder nada" do
      assert [reconstruida] = arbol() |> Zona.a_filas() |> Zona.desde_filas()
      assert reconstruida == arbol()
    end
  end

  describe "Zonas (proceso)" do
    setup do
      {:ok, z: "zona#{System.unique_integer([:positive])}"}
    end

    test "registra zonas, sectores y puntos y calcula estadísticas", %{z: z} do
      assert {:ok, _} = Zonas.registrar(z, "Norte", "crítico", 200)
      assert {:error, :duplicado} = Zonas.registrar(z, "Norte", :alto, 0)
      assert {:ok, _} = Zonas.agregar_sector(z, "#{z}-s1", "Sector", :alto, 50)
      assert {:ok, _} = Zonas.agregar_punto(z, "#{z}-s1", "#{z}-p1", "Punto", 10)
      assert {:ok, %{afectados: 260, sectores: 1, puntos: 1}} = Zonas.estadisticas(z)
      assert {:ok, %{nombre: "Norte", sectores: [%{codigo: _}]}} = Zonas.estado(z)
      assert Zonas.existe?(z)
    end

    test "errores esperados", %{z: z} do
      assert {:error, :no_existe} = Zonas.estadisticas("no_existe_#{z}")
      {:ok, _} = Zonas.registrar(z, "Norte", :bajo, 0)
      assert {:error, :padre_no_existe} = Zonas.agregar_punto(z, "nada", "p", "P", 0)
    end
  end
end
