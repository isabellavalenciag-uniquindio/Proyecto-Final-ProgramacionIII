defmodule PersonasTest do
  use ExUnit.Case

  defp doc, do: "#{System.unique_integer([:positive])}"

  describe "Persona (reglas puras)" do
    test "crea una persona con su primer estado en el historial" do
      assert {:ok, p} = Persona.nuevo("123", "Andrés", "norte", "localizada", 30)
      assert p.estado == :localizada
      assert [{:localizada, _fecha}] = p.historial
    end

    test "valida los datos" do
      assert {:error, :estado_invalido} = Persona.nuevo("1", "A", "z", "perdida")
      assert {:error, :edad_invalida} = Persona.nuevo("1", "A", "z", :reportada, -3)
      assert {:error, :edad_invalida} = Persona.nuevo("1", "A", "z", :reportada, 200)
      assert {:error, :texto_vacio} = Persona.nuevo("", "A", "z", :reportada)
    end

    test "los cambios de estado quedan en el historial" do
      {:ok, p} = Persona.nuevo("1", "A", "z", :reportada)
      {:ok, p} = Persona.cambiar_estado(p, :localizada)
      {:ok, p} = Persona.cambiar_estado(p, "en albergue")
      assert Enum.map(p.historial, &elem(&1, 0)) == [:en_albergue, :localizada, :reportada]
    end

    test "solo se permiten transiciones válidas" do
      {:ok, p} = Persona.nuevo("1", "A", "z", :en_albergue)
      assert {:error, :transicion_invalida} = Persona.cambiar_estado(p, :reportada)
      assert {:error, :mismo_estado} = Persona.cambiar_estado(p, :en_albergue)
      assert {:error, :estado_invalido} = Persona.cambiar_estado(p, :volando)
    end

    test "una persona reunificada no cambia más" do
      {:ok, p} = Persona.nuevo("1", "A", "z", :localizada)
      {:ok, p} = Persona.cambiar_estado(p, :reunificada)
      assert {:error, :ya_cerrada} = Persona.cambiar_estado(p, :localizada)
      assert {:error, :ya_cerrada} = Persona.cambiar_estado(p, :reunificada)
    end

    test "ida y vuelta al CSV" do
      {:ok, p} = Persona.nuevo("1", "Ana María", "z", :reportada, 12)
      {:ok, p} = Persona.cambiar_estado(p, :localizada)
      assert p |> Persona.a_fila() |> Persona.desde_fila() == p
    end
  end

  describe "Mensaje" do
    test "nace pendiente y se entrega una sola vez" do
      {:ok, m} = Mensaje.nuevo(1, "ana", "123", "Estoy bien")
      assert m.estado == :pendiente
      assert {:ok, entregado} = Mensaje.marcar_entregado(m)
      assert {:error, :ya_entregado} = Mensaje.marcar_entregado(entregado)
    end

    test "valida el contenido" do
      assert {:error, :texto_vacio} = Mensaje.nuevo(1, "ana", "123", "  ")
      assert {:error, :mensaje_largo} = Mensaje.nuevo(1, "ana", "123", String.duplicate("x", 501))
    end

    test "ida y vuelta al CSV" do
      {:ok, m} = Mensaje.nuevo(7, "ana", "123", "Estoy en el albergue norte")
      assert m |> Mensaje.a_fila() |> Mensaje.desde_fila() == m
    end
  end

  describe "Personas (proceso)" do
    setup do
      zona = "zona#{System.unique_integer([:positive])}"
      {:ok, _} = Zonas.registrar(zona, "Zona de prueba", :alto)
      {:ok, zona: zona}
    end

    test "registra y busca por documento, nombre, zona y estado", ctx do
      d = doc()
      zona = ctx.zona
      {:ok, _} = Personas.reportar(d, "Andrés Gómez", zona, "localizada", 30)

      assert [%Persona{documento: ^d}] = Personas.buscar(documento: d)
      assert [%Persona{}] = Personas.buscar(nombre: "andres", zona: zona)
      assert [%Persona{}] = Personas.buscar(zona: zona, estado: :localizada)
      assert [] = Personas.buscar(zona: zona, estado: :reunificada)
    end

    test "no repite documentos", ctx do
      d = doc()
      {:ok, _} = Personas.reportar(d, "A", ctx.zona, :reportada)
      assert {:error, :duplicado} = Personas.reportar(d, "B", ctx.zona, :reportada)
    end

    test "actualiza el estado y conserva el historial", ctx do
      d = doc()
      {:ok, _} = Personas.reportar(d, "A", ctx.zona, :reportada)
      assert {:ok, %Persona{estado: :localizada}} = Personas.actualizar_estado(d, :localizada)
      assert {:ok, [{:localizada, _}, {:reportada, _}]} = Personas.historial(d)
      assert {:error, :no_existe} = Personas.actualizar_estado("no_existe_#{d}", :localizada)
    end

    test "guarda mensajes, los lista y los entrega una sola vez" do
      d = doc()
      {:ok, m1} = Personas.enviar_mensaje("ana", d, "Estoy bien, estoy en el albergue norte")
      {:ok, m2} = Personas.enviar_mensaje("luis", d, "Te buscamos")

      assert m2.id == m1.id + 1
      assert [%Mensaje{estado: :pendiente}, %Mensaje{}] = Personas.mensajes(d)
      assert {:ok, %Mensaje{estado: :entregado}} = Personas.marcar_entregado(m1.id)
      assert {:error, :ya_entregado} = Personas.marcar_entregado(m1.id)
      assert {:error, :no_existe} = Personas.marcar_entregado(-1)
      assert [%Mensaje{estado: :entregado}, %Mensaje{estado: :pendiente}] = Personas.mensajes(d)
    end

    test "10 reportes simultáneos del mismo documento: solo uno se registra", ctx do
      d = doc()

      resultados =
        1..10
        |> Enum.map(fn _ -> Task.async(fn -> Personas.reportar(d, "A", ctx.zona, :reportada) end) end)
        |> Task.await_many()

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &match?({:error, :duplicado}, &1)) == 9
    end
  end
end
