defmodule ComandosTest do
  use ExUnit.Case

  setup do
    n = System.unique_integer([:positive])
    {:ok, n: n, zona: "zona#{n}", categoria: "agua#{n}", ubicacion: "centro#{n}"}
  end

  # Ejecuta varias líneas seguidas sobre la misma sesión y devuelve el último resultado
  defp correr(lineas, sesion) do
    Enum.reduce(lineas, {:ok, "", sesion}, fn linea, {_, _, s} -> Emergencias.ejecutar(linea, s) end)
  end

  # El nombre de usuario lleva el tipo, un sufijo opcional y un número único
  defp sesion_como(tipo, n, zona, sufijo \\ "") do
    {:ok, _, sesion} = Emergencias.ejecutar("connect #{tipo}#{sufijo}#{n} 1234 #{tipo} #{zona}", Emergencias.nueva_sesion())
    sesion
  end

  describe "tokenizar/1" do
    test "separa por espacios y respeta las comillas" do
      assert Comandos.tokenizar("a  b   c") == ["a", "b", "c"]
      assert Comandos.tokenizar(~s(send_family_message 123 "Estoy bien, estoy aquí")) ==
               ["send_family_message", "123", "Estoy bien, estoy aquí"]
    end

    test "línea vacía y comillas sin cerrar" do
      assert Comandos.tokenizar("   ") == []
      assert {:error, :comillas_sin_cerrar} = Comandos.tokenizar(~s(a "b c))
    end
  end

  describe "sesión y permisos" do
    test "sin conectarse solo se puede help, connect y exit" do
      assert {:error, texto, _} = Emergencias.ejecutar("summary", Emergencias.nueva_sesion())
      assert texto =~ "conectarse"
      assert {:ok, ayuda, _} = Emergencias.ejecutar("help", Emergencias.nueva_sesion())
      assert ayuda =~ "connect"
    end

    test "comando desconocido y línea vacía" do
      assert {:error, texto, _} = Emergencias.ejecutar("volar", Emergencias.nueva_sesion())
      assert texto =~ "desconocido"
      assert {:ok, "", _} = Emergencias.ejecutar("", Emergencias.nueva_sesion())
    end

    test "connect registra automáticamente y valida la contraseña después", ctx do
      usuario = "laura#{ctx.n}"
      assert {:ok, texto, sesion} = Emergencias.ejecutar("connect #{usuario} 1234 coordinador centro", Emergencias.nueva_sesion())
      assert texto =~ "registrado y conectado"
      assert sesion.usuario.tipo == :coordinador

      assert {:ok, _, sin_sesion} = Emergencias.ejecutar("disconnect", sesion)
      assert sin_sesion.usuario == nil
      assert {:error, texto, _} = Emergencias.ejecutar("connect #{usuario} 0000", sin_sesion)
      assert texto =~ "Contraseña incorrecta"
      assert {:ok, texto, _} = Emergencias.ejecutar("connect #{usuario} 1234", sin_sesion)
      assert texto =~ "conectado como coordinador"
    end

    test "una sesión desconectada sigue invalidada aunque el usuario vuelva a conectarse", ctx do
      anterior = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("disconnect", anterior)
      actual = sesion_como("coordinador", ctx.n, ctx.zona)

      assert {:error, texto, %{usuario: nil}} = Emergencias.ejecutar("summary", anterior)
      assert texto =~ "conectarse"
      assert {:salir, _, _} = Emergencias.ejecutar("exit", anterior)
      assert {:ok, _, _} = Emergencias.ejecutar("summary", actual)
    end

    test "desconectar al usuario invalida todas sus sesiones", ctx do
      sesion = sesion_como("ciudadano", ctx.n, ctx.zona)
      assert :ok = Usuarios.desconectar(sesion.usuario.usuario)
      assert {:error, _, %{usuario: nil}} = Emergencias.ejecutar("summary", sesion)
    end

    test "cada conexión tiene su sesión y cerrar una conserva la otra", ctx do
      primera = sesion_como("ciudadano", ctx.n, ctx.zona)
      segunda = sesion_como("ciudadano", ctx.n, ctx.zona)
      refute primera.usuario.sesion_id == segunda.usuario.sesion_id

      assert {:ok, _, _} = Emergencias.ejecutar("disconnect", primera)
      assert {:error, _, _} = Emergencias.ejecutar("summary", primera)
      assert {:ok, _, _} = Emergencias.ejecutar("summary", segunda)
      assert Usuarios.conectado?(segunda.usuario.usuario)
    end

    test "los permisos se consultan con el rol guardado y no con un mapa modificado", ctx do
      sesion = sesion_como("ciudadano", ctx.n, ctx.zona)
      alterada = put_in(sesion, [:usuario, :tipo], :administrador)
      assert {:error, _, nueva} = Emergencias.ejecutar("list_users", alterada)
      assert nueva.usuario.tipo == :ciudadano
    end

    test "un ciudadano no puede ejecutar comandos de coordinador", ctx do
      sesion = sesion_como("ciudadano", ctx.n, ctx.zona)
      assert {:error, texto, _} = Emergencias.ejecutar("register_zone z1 Zona alto", sesion)
      assert texto =~ "no puede ejecutar"
      assert {:error, _, _} = Emergencias.ejecutar("assign_resource N001 agua 5", sesion)
      assert {:error, _, _} = Emergencias.ejecutar("list_users", sesion)
    end

    test "help muestra solo los comandos del rol", ctx do
      {:ok, ayuda, _} = Emergencias.ejecutar("help", sesion_como("ciudadano", ctx.n, ctx.zona))
      assert ayuda =~ "register_need"
      refute ayuda =~ "assign_resource"
    end

    test "exit cierra la sesión", ctx do
      sesion = sesion_como("voluntario", ctx.n, ctx.zona)
      assert {:salir, _, %{usuario: nil}} = Emergencias.ejecutar("exit", sesion)
      refute Usuarios.conectado?("voluntario#{ctx.n}")
    end
  end

  describe "validación de argumentos" do
    test "muestra el uso cuando faltan argumentos", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)
      assert {:error, "Uso: " <> uso, _} = Emergencias.ejecutar("assign_resource N001", sesion)
      assert uso =~ "assign_resource"
    end

    test "rechaza datos inválidos sin cambiar el estado", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("register_zone #{ctx.zona} Zona alto", sesion)

      assert {:error, t1, _} = Emergencias.ejecutar("register_need agua -5 alta #{ctx.zona}", sesion)
      assert t1 =~ "cantidad"
      assert {:error, t2, _} = Emergencias.ejecutar("register_need agua 5 urgente #{ctx.zona}", sesion)
      assert t2 =~ "Prioridad"
      assert {:error, t3, _} = Emergencias.ejecutar("register_need agua 5 alta zona_que_no_existe", sesion)
      assert t3 =~ "no existe"
      assert {:error, t4, _} = Emergencias.ejecutar("list_needs color=rojo", sesion)
      assert t4 =~ "Filtro inválido"
      assert {:error, _, _} = Emergencias.ejecutar("register_resource R1 agua -3 litros bodega", sesion)
    end
  end

  describe "flujo del enunciado" do
    test "necesidad, recurso, asignación y resumen", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)

      {:ok, _, _} = Emergencias.ejecutar("register_zone #{ctx.zona} Centro critico 500", sesion)
      {:ok, texto, _} = Emergencias.ejecutar(~s(register_need agua 30 critica #{ctx.zona} "Punto de atención sector 3"), sesion)
      assert texto =~ "Necesidad N"
      [id] = Regex.run(~r/N\d+/, texto)

      {:ok, _, _} = Emergencias.ejecutar("register_resource R#{ctx.n} agua 50 litros #{ctx.ubicacion} #{ctx.categoria}", sesion)
      {:ok, asignacion, _} = Emergencias.ejecutar("assign_resource #{id} #{ctx.categoria} 30", sesion)
      assert asignacion =~ "30/30"
      assert Inventario.disponibilidad(ctx.categoria) == 20

      {:ok, listado, _} = Emergencias.ejecutar("list_needs zona=#{ctx.zona} estado=asignada", sesion)
      assert listado =~ id
      {:ok, resumen, _} = Emergencias.ejecutar("summary", sesion)
      assert resumen =~ "#{ctx.categoria}: 20 litros"
    end

    test "need_status cancelada devuelve los recursos y no permite devolverlos otra vez", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _} = Inventario.registrar("R#{ctx.n}", "Agua", ctx.categoria, 50, "litros", ctx.ubicacion)
      {:ok, n} = Necesidades.registrar(:agua, 30, :alta, ctx.zona, "", sesion.usuario.usuario)
      {:ok, _} = Necesidades.asignar(n.id, ctx.categoria, 30)

      assert {:ok, _, _} = Emergencias.ejecutar("need_status #{n.id} cancelada", sesion)
      assert Inventario.disponibilidad(ctx.categoria) == 50
      assert {:error, _, _} = Emergencias.ejecutar("cancel_need #{n.id}", sesion)
      assert Inventario.disponibilidad(ctx.categoria) == 50
    end

    test "el id de la necesidad se acepta como need001, n1 o N001", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("register_zone #{ctx.zona} Centro alto", sesion)
      {:ok, texto, _} = Emergencias.ejecutar("register_need agua 5 alta #{ctx.zona} desc", sesion)
      [id] = Regex.run(~r/N\d+/, texto)
      numero = id |> String.trim_leading("N") |> String.to_integer()

      assert {:ok, _, _} = Emergencias.ejecutar("need_status need#{numero} cancelada", sesion)
      assert {:error, texto, _} = Emergencias.ejecutar("need_status n#{numero} cancelada", sesion)
      assert texto =~ "cerrada"
    end

    test "personas, mensajes y albergue", ctx do
      coordinador = sesion_como("coordinador", ctx.n, ctx.zona)
      ciudadano = sesion_como("ciudadano", ctx.n, ctx.zona)
      voluntario = sesion_como("voluntario", ctx.n, ctx.zona)
      doc = "#{ctx.n}"

      {:ok, _, _} = Emergencias.ejecutar("register_zone #{ctx.zona} Norte alto", coordinador)
      {:ok, _, _} = Emergencias.ejecutar(~s(register_shelter A#{ctx.n} "Albergue Norte" #{ctx.zona} 2), coordinador)

      {:ok, t, _} = Emergencias.ejecutar("report_person #{doc} Andrés #{ctx.zona} localizada 30", ciudadano)
      assert t =~ "registrada como localizada"
      assert {:error, _, _} = Emergencias.ejecutar("report_person #{doc} Otro #{ctx.zona} localizada", ciudadano)

      {:ok, _, _} = Emergencias.ejecutar(~s(send_family_message #{doc} "Estoy bien, estoy en el albergue norte"), ciudadano)
      {:ok, mensajes, _} = Emergencias.ejecutar("list_family_messages #{doc}", ciudadano)
      assert mensajes =~ "Estoy bien, estoy en el albergue norte"
      assert mensajes =~ "[pendiente]"

      {:ok, ingreso, _} = Emergencias.ejecutar("register_entry A#{ctx.n} #{doc}", voluntario)
      assert ingreso =~ "1/2"
      {:ok, persona, _} = Emergencias.ejecutar("find_person #{doc}", ciudadano)
      assert persona =~ "en_albergue"

      {:ok, _, _} = Emergencias.ejecutar("register_entry A#{ctx.n} otra#{ctx.n}", voluntario)
      assert {:error, lleno, _} = Emergencias.ejecutar("register_entry A#{ctx.n} tercera#{ctx.n}", voluntario)
      assert lleno =~ "cupos"
      {:ok, estado, _} = Emergencias.ejecutar("check_shelter A#{ctx.n}", ciudadano)
      assert estado =~ "2/2"
    end

    test "la salida del albergue actualiza el estado de la persona y su historial", ctx do
      sesion = sesion_como("voluntario", ctx.n, ctx.zona)
      documento = "salida#{ctx.n}"
      albergue = "AS#{ctx.n}"
      {:ok, _} = Personas.reportar(documento, "Ana", ctx.zona, :localizada, 20)
      {:ok, _} = Albergues.registrar(albergue, "Norte", ctx.zona, 2)
      {:ok, _, _} = Emergencias.ejecutar("register_entry #{albergue} #{documento}", sesion)

      assert {:ok, _, _} = Emergencias.ejecutar("register_exit #{albergue} #{documento}", sesion)
      assert {:ok, %{ocupacion: 0, cupos: 2}} = Albergues.consultar(albergue)
      assert {:ok, %Persona{estado: :trasladada}} = Personas.obtener(documento)
      assert {:ok, [{:trasladada, _}, {:en_albergue, _}, {:localizada, _}]} = Personas.historial(documento)
    end

    test "una salida fallida no cambia el estado de la persona", ctx do
      sesion = sesion_como("voluntario", ctx.n, ctx.zona)
      documento = "ausente#{ctx.n}"
      albergue = "AS#{ctx.n}"
      {:ok, _} = Personas.reportar(documento, "Ana", ctx.zona, :en_albergue, 20)
      {:ok, _} = Albergues.registrar(albergue, "Norte", ctx.zona, 2)

      assert {:error, _, _} = Emergencias.ejecutar("register_exit #{albergue} #{documento}", sesion)
      assert {:ok, %Persona{estado: :en_albergue}} = Personas.obtener(documento)
    end

    test "la salida respeta una reunificación y admite ocupantes sin reporte de persona", ctx do
      sesion = sesion_como("voluntario", ctx.n, ctx.zona)
      documento = "reunificada#{ctx.n}"
      sin_reporte = "sin_reporte#{ctx.n}"
      albergue = "AS#{ctx.n}"
      {:ok, _} = Personas.reportar(documento, "Ana", ctx.zona, :en_albergue, 20)
      {:ok, _} = Albergues.registrar(albergue, "Norte", ctx.zona, 2)
      {:ok, _} = Albergues.ingresar(albergue, documento)
      {:ok, _} = Albergues.ingresar(albergue, sin_reporte)
      {:ok, _} = Personas.actualizar_estado(documento, :reunificada)

      assert {:ok, _, _} = Emergencias.ejecutar("register_exit #{albergue} #{documento}", sesion)
      assert {:ok, %Persona{estado: :reunificada}} = Personas.obtener(documento)
      assert {:ok, _, _} = Emergencias.ejecutar("register_exit #{albergue} #{sin_reporte}", sesion)
      assert {:ok, %{ocupacion: 0}} = Albergues.consultar(albergue)
    end

    test "mascotas: reportar, coincidencias y confirmar", ctx do
      voluntario = sesion_como("voluntario", ctx.n, ctx.zona)
      coordinador = sesion_como("coordinador", ctx.n, ctx.zona)
      especie = "especie#{ctx.n}"

      {:ok, t1, _} = Emergencias.ejecutar(~s(report_pet lost #{especie} "Luna" negra mediana #{ctx.zona} 300), voluntario)
      {:ok, t2, _} = Emergencias.ejecutar(~s(report_pet found #{especie} desconocido negra mediana #{ctx.zona} 301), voluntario)
      [perdida] = Regex.run(~r/M\d+/, t1)
      [encontrada] = Regex.run(~r/M\d+/, t2)

      {:ok, pares, _} = Emergencias.ejecutar("match_pets", voluntario)
      assert pares =~ "#{perdida} (perdida) ~ #{encontrada} (encontrada)"

      assert {:error, _, _} = Emergencias.ejecutar("confirm_match #{perdida} #{encontrada}", voluntario)
      assert {:ok, confirmado, _} = Emergencias.ejecutar("confirm_match #{perdida} #{encontrada}", coordinador)
      assert confirmado =~ "resueltas"
      assert {:error, repetido, _} = Emergencias.ejecutar("confirm_match #{perdida} #{encontrada}", coordinador)
      assert repetido =~ "ya está resuelto"
    end

    test "transferencias entre centros", ctx do
      sesion = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("register_resource R#{ctx.n} agua 200 litros #{ctx.ubicacion} #{ctx.categoria}", sesion)
      {:ok, texto, _} = Emergencias.ejecutar("transfer_resource R#{ctx.n} #{ctx.ubicacion} albergue_#{ctx.n} 30", sesion)
      assert texto =~ "170"
      assert {:error, _, _} = Emergencias.ejecutar("transfer_resource R#{ctx.n} #{ctx.ubicacion} albergue_#{ctx.n} 500", sesion)
      assert Inventario.disponibilidad(ctx.categoria) == 200
    end
  end

  describe "actividad" do
    test "se registra lo que hace cada usuario, sin la contraseña", ctx do
      sesion = sesion_como("ciudadano", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("summary", sesion)
      usuario = "ciudadano#{ctx.n}"

      comandos = Usuarios.actividad(usuario) |> Enum.map(fn {_u, _f, c} -> c end)
      assert "summary" in comandos
      assert "connect #{usuario}" in comandos
      refute Enum.any?(comandos, &String.contains?(&1, "1234"))
    end

    test "solo el administrador ve la actividad", ctx do
      assert {:error, _, _} = Emergencias.ejecutar("activity", sesion_como("coordinador", ctx.n, ctx.zona))
      assert {:ok, _, _} = Emergencias.ejecutar("activity", sesion_como("administrador", ctx.n, ctx.zona))
    end
  end

  describe "concurrencia entre usuarios" do
    test "dos coordinadores piden 30 y 25 L de 50 disponibles a la vez: solo una asignación se confirma", ctx do
      admin = sesion_como("coordinador", ctx.n, ctx.zona)
      {:ok, _, _} = Emergencias.ejecutar("register_zone #{ctx.zona} Centro critico", admin)
      {:ok, _, _} = Emergencias.ejecutar("register_resource R#{ctx.n} agua 50 litros #{ctx.ubicacion} #{ctx.categoria}", admin)
      {:ok, a, _} = Emergencias.ejecutar("register_need agua 30 critica #{ctx.zona} Laura", admin)
      {:ok, b, _} = Emergencias.ejecutar("register_need agua 25 alta #{ctx.zona} Pedro", admin)
      [id_a] = Regex.run(~r/N\d+/, a)
      [id_b] = Regex.run(~r/N\d+/, b)

      resultados =
        [{"uno", id_a, 30}, {"dos", id_b, 25}]
        |> Enum.map(fn {quien, id, cantidad} ->
          Task.async(fn ->
            sesion = sesion_como("coordinador", ctx.n, ctx.zona, quien)
            elem(Emergencias.ejecutar("assign_resource #{id} #{ctx.categoria} #{cantidad}", sesion), 0)
          end)
        end)
        |> Task.await_many()

      assert Enum.sort(resultados) == [:error, :ok]
      assert Inventario.disponibilidad(ctx.categoria) in [20, 25]
    end

    test "demo_conflicto del módulo Emergencias" do
      %{resultados: resultados, existencias_finales: finales} = Emergencias.demo_conflicto()
      assert length(resultados) == 2
      assert finales in [20, 25]
    end
  end
end
