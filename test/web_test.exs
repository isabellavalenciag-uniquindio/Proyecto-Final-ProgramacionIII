defmodule EmergenciasWebTest do
  use ExUnit.Case
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Emergencias.SesionesWeb
  alias EmergenciasWeb.Operaciones
  @endpoint EmergenciasWeb.Endpoint

  setup do
    id = "web#{System.unique_integer([:positive])}"
    {:ok, _} = Zonas.registrar(id, "Zona de prueba web", :alto)

    {:ok, _, sesion} =
      Comandos.ejecutar_operacion(
        :connect,
        [id, "clave-prueba", "administrador", id, "Coordinadora Web"],
        Emergencias.nueva_sesion()
      )

    {:ok, token} = SesionesWeb.crear(sesion)
    conn = build_conn() |> init_test_session(%{"token" => token})
    {:ok, id: id, sesion: sesion, token: token, conn: conn}
  end

  test "el acceso se muestra y el panel exige una sesión auténtica" do
    conn = get(build_conn(), "/acceso")
    assert html_response(conn, 200) =~ "La ayuda empieza"
    assert {:error, {:redirect, %{to: "/acceso"}}} = live(build_conn(), "/")
    conn = build_conn() |> init_test_session(%{"token" => "inventado"})
    assert {:error, {:redirect, %{to: "/acceso"}}} = live(conn, "/")
  end

  test "las operaciones estructuradas conservan comillas y validan permisos", ctx do
    nombre = ~s(Zona "Puerta norte")

    assert {:ok, _, _} =
             Comandos.ejecutar_operacion(
               :register_zone,
               [ctx.id <> "nueva", nombre, "alto", "10"],
               ctx.sesion
             )

    assert {:ok, %{nombre: ^nombre}} = Zonas.obtener(ctx.id <> "nueva")

    {:ok, _, ciudadano} =
      Comandos.ejecutar_operacion(
        :connect,
        [ctx.id <> "civil", "1234", "ciudadano", ctx.id],
        Emergencias.nueva_sesion()
      )

    assert {:error, _, _} =
             Comandos.ejecutar_operacion(
               :register_zone,
               [ctx.id <> "prohibida", "Zona", "alto"],
               ciudadano
             )

    assert {:error, :no_existe} = Zonas.obtener(ctx.id <> "prohibida")
    assert {:error, _, _} = Comandos.ejecutar_operacion("accion_desconocida", [], ctx.sesion)
    assert {:error, _, _} = Comandos.ejecutar_operacion(:register_zone, [%{}], ctx.sesion)
  end

  test "el acceso estructurado no guarda contraseñas en la actividad", ctx do
    actividades = Usuarios.actividad(ctx.id)
    refute Enum.any?(actividades, fn {_, _, linea} -> String.contains?(linea, "clave-prueba") end)
  end

  test "el token web respeta la identidad guardada y su revocación", ctx do
    {:ok, sesion} = SesionesWeb.obtener(ctx.token)
    assert sesion.usuario.usuario == ctx.id
    assert :ok = SesionesWeb.cerrar(ctx.token)
    assert {:error, :sin_sesion} = SesionesWeb.obtener(ctx.token)
    refute Usuarios.conectado?(ctx.id)

    assert {:error, :sin_sesion} =
             SesionesWeb.crear(%{usuario: %{usuario: ctx.id, sesion_id: make_ref()}})

    assert {:error, :sin_sesion} = SesionesWeb.crear(%{})
  end

  test "una sesión web vencida deja de mantener conectado al usuario", ctx do
    :sys.replace_state(SesionesWeb, fn estado ->
      Map.update!(estado, ctx.token, fn {sesion, _} ->
        {sesion, System.monotonic_time(:second) - 1}
      end)
    end)

    assert {:error, :sin_sesion} = SesionesWeb.obtener(ctx.token)
    refute Usuarios.conectado?(ctx.id)
  end

  test "el panel registra una necesidad desde un formulario", ctx do
    {:ok, view, html} = live(ctx.conn, "/panel/necesidades")
    assert html =~ "Necesidades"
    view |> element(".heading-actions button[phx-value-accion=register_need]") |> render_click()

    valores = %{
      tipo: "agua",
      cantidad: "10",
      prioridad: "critica",
      zona: ctx.id,
      descripcion: ~s(Agua para "la plaza")
    }

    view |> form("#form-operacion", operacion: valores) |> render_submit()

    assert [%Necesidad{descripcion: ~s(Agua para "la plaza"), prioridad: :critica}] =
             Necesidades.listar(zona: ctx.id)

    refute has_element?(view, "#form-operacion")
    assert render(view) =~ "Necesidad"
  end

  test "el servidor impide abrir formularios que el rol no autoriza", ctx do
    {:ok, _, ciudadano} =
      Comandos.ejecutar_operacion(
        :connect,
        [ctx.id <> "civil", "1234", "ciudadano", ctx.id],
        Emergencias.nueva_sesion()
      )

    {:ok, token} = SesionesWeb.crear(ciudadano)
    conn = build_conn() |> init_test_session(%{"token" => token})
    {:ok, view, _} = live(conn, "/panel/recursos")
    refute has_element?(view, "[phx-value-accion=register_resource]")
    assert render_click(view, "abrir", %{"accion" => "register_resource"}) =~ "Tu rol no permite"
    refute has_element?(view, "#form-operacion")
    render_submit(view, "guardar", %{"operacion" => %{"codigo" => ctx.id <> "falso"}})
    assert Inventario.listar(codigo: ctx.id <> "falso") == []
  end

  test "los cambios de la consola actualizan la pantalla conectada", ctx do
    {:ok, view, _} = live(ctx.conn, "/panel/necesidades")
    texto = "Solicitud compartida #{ctx.id}"

    {:ok, _, _} =
      Emergencias.ejecutar(
        ~s(register_need agua 3 alta #{ctx.id} "#{texto}"),
        ctx.sesion
      )

    :ok = Persistencia.sincronizar()
    assert render(view) =~ texto
  end

  test "se pueden abrir todas las pantallas con los datos reales", ctx do
    for seccion <- ~w(zonas recursos personas mensajes mascotas albergues actividad) do
      {:ok, view, html} = live(ctx.conn, "/panel/#{seccion}")
      assert html =~ "nexo-app"
      refute html =~ "clave-prueba"
      GenServer.stop(view.pid, :normal)
    end
  end

  test "los errores de formulario no modifican el dominio", ctx do
    assert {:error, _, _, errores} =
             Operaciones.ejecutar(
               "register_need",
               %{"tipo" => "agua", "cantidad" => %{}, "zona" => ctx.id, "prioridad" => "alta"},
               ctx.sesion
             )

    assert errores["cantidad"]
    assert Necesidades.listar(zona: ctx.id) == []
    assert {:error, _, _, _} = Operaciones.ejecutar("desconocida", %{}, ctx.sesion)
  end

  test "revocar la sesión original expulsa al usuario de la vista", ctx do
    {:ok, view, _} = live(ctx.conn, "/")
    :ok = Usuarios.desconectar(ctx.id)
    send(view.pid, :verificar_sesion)
    assert_redirect(view, "/acceso")
    assert {:error, :sin_sesion} = SesionesWeb.obtener(ctx.token)
  end

  test "la ruta de acceso crea la cookie y cerrar sesión revoca su token", ctx do
    conn =
      post(build_conn(), "/sesion", %{
        "acceso" => %{"usuario" => ctx.id, "clave" => "clave-prueba"}
      })

    assert redirected_to(conn) == "/"
    token = get_session(conn, :token)
    assert is_binary(token)
    assert {:ok, _} = SesionesWeb.obtener(token)
    conn = conn |> recycle() |> post("/salir", %{})
    assert redirected_to(conn) == "/acceso"
    assert {:error, :sin_sesion} = SesionesWeb.obtener(token)
  end
end
