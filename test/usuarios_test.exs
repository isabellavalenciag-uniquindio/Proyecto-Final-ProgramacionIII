defmodule UsuariosTest do
  use ExUnit.Case

  defp nuevo_nombre, do: "usr#{System.unique_integer([:positive])}"

  describe "Usuario (reglas puras)" do
    test "crea un usuario y guarda la contraseña como hash" do
      assert {:ok, u} = Usuario.nuevo("Laura", "1234", "Laura Pérez", "coordinador", "centro")
      assert u.usuario == "laura"
      assert u.tipo == :coordinador
      refute u.clave_hash == "1234"
      assert Usuario.verificar_clave(u, "1234")
      refute Usuario.verificar_clave(u, "9999")
    end

    test "valida los datos" do
      assert {:error, :usuario_invalido} = Usuario.nuevo("a b", "1234", "n", "ciudadano", "z")
      assert {:error, :usuario_invalido} = Usuario.nuevo("", "1234", "n", "ciudadano", "z")
      assert {:error, :clave_corta} = Usuario.nuevo("ana", "12", "n", "ciudadano", "z")
      assert {:error, :tipo_invalido} = Usuario.nuevo("ana", "1234", "n", "jefe", "z")
      assert {:error, :texto_vacio} = Usuario.nuevo("ana", "1234", "n", "ciudadano", " ")
    end

    test "ida y vuelta al CSV" do
      {:ok, u} = Usuario.nuevo("ana", "1234", "Ana Gómez", :voluntario, "norte")
      assert u |> Usuario.a_fila() |> Usuario.desde_fila() == u
    end
  end

  describe "Permisos" do
    test "los roles son acumulativos" do
      assert Permisos.permitido?(:ciudadano, :register_need)
      refute Permisos.permitido?(:ciudadano, :assign_resource)
      assert Permisos.permitido?(:voluntario, :register_need)
      assert Permisos.permitido?(:voluntario, :register_entry)
      refute Permisos.permitido?(:voluntario, :register_zone)
      assert Permisos.permitido?(:coordinador, :assign_resource)
      refute Permisos.permitido?(:coordinador, :list_users)
      assert Permisos.permitido?(:administrador, :list_users)
      assert Permisos.permitido?(:administrador, :assign_resource)
    end

    test "un tipo desconocido no puede nada" do
      assert Permisos.comandos(:intruso) == []
    end

    test "todo comando (salvo los de sesión) lo puede ejecutar el administrador" do
      sesion = [:connect, :help, :exit]

      for comando <- Comandos.todos() -- sesion do
        assert Permisos.permitido?(:administrador, comando), "falta permiso para #{comando}"
      end
    end
  end

  describe "Usuarios (proceso)" do
    test "el registro automático conserva el nombre completo en futuras conexiones" do
      usuario = nuevo_nombre()
      assert {:ok, %{nombre: "Ana María Gómez"}} =
               Usuarios.conectar(usuario, "1234", :ciudadano, "norte", "Ana María Gómez")
      assert {:ok, %{nombre: "Ana María Gómez", tipo: :ciudadano, zona: "norte"}} =
               Usuarios.conectar(usuario, "1234", :administrador, "sur", "Otro nombre")
      assert [fila] = Persistencia.cargar(:usuarios) |> Enum.filter(&(hd(&1) == usuario))
      assert %Usuario{nombre: "Ana María Gómez"} = Usuario.desde_fila(fila)
    end

    test "si el usuario no existe se registra automáticamente" do
      nombre = nuevo_nombre()
      assert {:ok, %{nuevo: true, tipo: :coordinador, zona: "centro"}} = Usuarios.conectar(nombre, "1234", "coordinador", "centro")
      assert Usuarios.conectado?(nombre)
    end

    test "si ya existe se valida la contraseña" do
      nombre = nuevo_nombre()
      {:ok, _} = Usuarios.conectar(nombre, "1234", "ciudadano", "norte")
      :ok = Usuarios.desconectar(nombre)

      assert {:error, :clave_incorrecta} = Usuarios.conectar(nombre, "0000", "ciudadano", "norte")
      assert {:ok, %{nuevo: false}} = Usuarios.conectar(nombre, "1234", "administrador", "otra")
      # El tipo guardado no cambia aunque se pida otro
      assert {:ok, %{tipo: :ciudadano}} = Usuarios.conectar(nombre, "1234", "administrador", "otra")
    end

    test "desconectar" do
      nombre = nuevo_nombre()
      {:ok, _} = Usuarios.conectar(nombre, "1234", "ciudadano", "z")
      assert :ok = Usuarios.desconectar(nombre)
      refute Usuarios.conectado?(nombre)
      assert {:error, :no_conectado} = Usuarios.desconectar(nombre)
    end

    test "valida sesiones emitidas y rechaza las revocadas o inventadas" do
      nombre = nuevo_nombre()
      {:ok, sesion} = Usuarios.conectar(nombre, "1234", "ciudadano", "z")
      assert {:ok, %{usuario: ^nombre}} = Usuarios.validar_sesion(sesion)
      assert {:error, :sin_sesion} = Usuarios.validar_sesion(%{usuario: nombre})
      assert {:error, :sin_sesion} = Usuarios.validar_sesion(%{usuario: nombre, sesion_id: make_ref()})
      refute Enum.any?(Usuarios.listar(), &Map.has_key?(&1, :sesion_id))

      assert :ok = Usuarios.desconectar(nombre, sesion.sesion_id)
      assert {:error, :sin_sesion} = Usuarios.validar_sesion(sesion)
    end

    test "registrar no permite repetidos" do
      nombre = nuevo_nombre()
      assert {:ok, _} = Usuarios.registrar(nombre, "1234", "Nombre", "voluntario", "z")
      assert {:error, :duplicado} = Usuarios.registrar(nombre, "1234", "Nombre", "voluntario", "z")
    end

    test "registra la actividad de cada usuario" do
      nombre = nuevo_nombre()
      {:ok, _} = Usuarios.conectar(nombre, "1234", "ciudadano", "z")
      Usuarios.registrar_actividad(nombre, "register_need agua 5 alta z")
      Usuarios.registrar_actividad(nombre, "summary")

      assert [{^nombre, _fecha, "summary"}, {^nombre, _, "register_need agua 5 alta z"}] = Usuarios.actividad(nombre)
    end

    test "20 conexiones simultáneas del mismo usuario nuevo: solo una lo registra" do
      nombre = nuevo_nombre()

      resultados =
        1..20
        |> Enum.map(fn _ -> Task.async(fn -> Usuarios.conectar(nombre, "1234", "ciudadano", "z") end) end)
        |> Task.await_many()

      assert Enum.all?(resultados, &match?({:ok, _}, &1))
      assert Enum.count(resultados, fn {:ok, info} -> info.nuevo end) == 1
    end

    test "listar no expone contraseñas" do
      nombre = nuevo_nombre()
      {:ok, _} = Usuarios.conectar(nombre, "1234", "ciudadano", "z")
      usuario = Enum.find(Usuarios.listar(), &(&1.usuario == nombre))
      assert usuario.conectado
      refute Map.has_key?(usuario, :clave_hash)
    end
  end
end
