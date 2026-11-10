defmodule ValidacionTest do
  use ExUnit.Case, async: true

  describe "atomo/3" do
    test "reconoce texto sin importar mayúsculas, tildes ni espacios" do
      assert {:ok, :critica} = Validacion.atomo("Crítica", [:critica, :alta])
      assert {:ok, :primeros_auxilios} = Validacion.atomo("Primeros Auxilios", [:primeros_auxilios])
      assert {:ok, :alta} = Validacion.atomo("  ALTA ", [:critica, :alta])
    end

    test "acepta un átomo válido y rechaza uno inválido" do
      assert {:ok, :alta} = Validacion.atomo(:alta, [:critica, :alta])
      assert {:error, :prioridad_invalida} = Validacion.atomo(:otra, [:critica, :alta], :prioridad_invalida)
    end

    test "rechaza valores que no son texto ni átomo" do
      assert {:error, :invalido} = Validacion.atomo(5, [:a])
      assert {:error, :invalido} = Validacion.atomo(nil, [:a])
    end
  end

  describe "enteros" do
    test "entero_positivo acepta enteros y texto numérico" do
      assert {:ok, 5} = Validacion.entero_positivo(5)
      assert {:ok, 30} = Validacion.entero_positivo(" 30 ")
    end

    test "entero_positivo rechaza cero, negativos y basura" do
      for malo <- [0, -1, "0", "-4", "abc", "3.5", "12x", nil, 2.5] do
        assert {:error, :cantidad_invalida} = Validacion.entero_positivo(malo)
      end
    end

    test "entero_no_negativo admite el cero pero no negativos" do
      assert {:ok, 0} = Validacion.entero_no_negativo(0)
      assert {:ok, 0} = Validacion.entero_no_negativo("0")
      assert {:error, :cantidad_invalida} = Validacion.entero_no_negativo(-1)
      assert {:error, :cantidad_invalida} = Validacion.entero_no_negativo("x")
    end
  end

  describe "texto/1" do
    test "recorta espacios y rechaza vacíos" do
      assert {:ok, "hola"} = Validacion.texto("  hola ")
      assert {:error, :texto_vacio} = Validacion.texto("   ")
      assert {:error, :texto_vacio} = Validacion.texto(nil)
    end
  end

  describe "normalizar/1 y coincide?/2" do
    test "normaliza tildes, mayúsculas y espacios" do
      assert Validacion.normalizar("  Árbol Grande ") == "arbol_grande"
    end

    test "coincide? compara sin distinguir formato" do
      assert Validacion.coincide?("Agua", "agua")
      assert Validacion.coincide?(:en_atencion, "En Atención")
      refute Validacion.coincide?("agua", "alimentos")
    end
  end
end
