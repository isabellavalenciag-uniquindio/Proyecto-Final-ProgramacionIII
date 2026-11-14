defmodule EmergenciasWeb.PanelLive do
  use EmergenciasWeb, :live_view
  alias Emergencias.SesionesWeb
  embed_templates "panel_live/*"

  @impl true
  def mount(_, session, socket) do
    case SesionesWeb.obtener(session["token"]) do
      {:ok, sesion} ->
        if connected?(socket) do
          Emergencias.Eventos.suscribir()
          Process.send_after(self(), :verificar_sesion, 30_000)
        end

        socket =
          assign(socket,
            token: session["token"],
            sesion: sesion,
            usuario: sesion.usuario,
            seccion: Presentacion.seccion("inicio"),
            secciones: Presentacion.secciones(),
            page_title: "Panorama",
            consulta: "",
            zona: "",
            menu: false,
            accion: nil,
            valores: %{},
            errores: %{},
            aviso: nil,
            detalle: nil
          )

        {:ok, recargar(socket)}

      _ ->
        {:ok, redirect(socket, to: "/acceso")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    if socket.assigns[:usuario] do
      seccion = Presentacion.seccion(params["seccion"] || "inicio")

      if seccion do
        {:noreply,
         assign(socket,
           seccion: seccion,
           page_title: seccion.nombre,
           consulta: "",
           zona: "",
           menu: false,
           accion: nil,
           detalle: nil
         )}
      else
        {:noreply, push_patch(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("menu", _, socket), do: {:noreply, update(socket, :menu, &(!&1))}

  def handle_event("cerrar", _, socket),
    do: {:noreply, assign(socket, accion: nil, detalle: nil, errores: %{})}

  def handle_event("cerrar_aviso", _, socket), do: {:noreply, assign(socket, :aviso, nil)}

  def handle_event("limpiar_filtros", _, socket),
    do: {:noreply, assign(socket, consulta: "", zona: "")}

  def handle_event("filtrar", %{"filtros" => params}, socket) when is_map(params) do
    consulta = params["consulta"]
    zona = params["zona"]

    if is_binary(consulta) and is_binary(zona),
      do: {:noreply, assign(socket, consulta: String.slice(consulta, 0, 120), zona: zona)},
      else: {:noreply, socket}
  end

  def handle_event("abrir", %{"accion" => id} = params, socket) do
    con_sesion(socket, fn socket ->
      accion = Operaciones.buscar(id)

      if accion && Permisos.permitido?(socket.assigns.usuario.tipo, accion.comando) do
        claves = Enum.map(accion.campos, & &1.clave)
        iniciales = Operaciones.iniciales(accion)
        zona = socket.assigns.usuario.zona

        iniciales =
          if "zona" in claves and Enum.any?(socket.assigns.datos.zonas, &(&1.codigo == zona)),
            do: Map.put(iniciales, "zona", zona),
            else: iniciales

        valores = Map.merge(iniciales, Map.take(params, claves))
        {:noreply, assign(socket, accion: accion, valores: valores, errores: %{}, detalle: nil)}
      else
        {:noreply, avisar(socket, :error, "Tu rol no permite realizar esta operación.")}
      end
    end)
  end

  def handle_event("validar", %{"operacion" => valores}, socket) when is_map(valores) do
    if socket.assigns.accion do
      claves = Enum.map(socket.assigns.accion.campos, & &1.clave)
      valores = Map.take(valores, claves)
      {:noreply, assign(socket, valores: valores, errores: %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guardar", params, socket) do
    con_sesion(socket, fn socket ->
      case socket.assigns.accion do
        nil ->
          {:noreply, socket}

        accion ->
          valores = Map.get(params, "operacion", %{})

          case Operaciones.ejecutar(accion.id, valores, socket.assigns.sesion) do
            {:ok, texto, nueva} ->
              texto =
                if accion.id == "match_pets",
                  do: "Búsqueda completada. Revisa las posibles coincidencias en esta pantalla.",
                  else: texto

              socket =
                socket
                |> assign(sesion: nueva, accion: nil, valores: %{}, errores: %{})
                |> recargar()
                |> avisar(:ok, texto)

              {:noreply, socket}

            {:error, texto, nueva, errores} ->
              {:noreply,
               socket |> assign(sesion: nueva, errores: errores) |> avisar(:error, texto)}
          end
      end
    end)
  end

  def handle_event("historial_persona", %{"documento" => documento}, socket) do
    con_sesion(socket, fn socket ->
      case Personas.obtener(documento) do
        {:ok, persona} ->
          {:noreply, assign(socket, detalle: %{tipo: :persona, registro: persona}, accion: nil)}

        _ ->
          {:noreply, avisar(socket, :error, "La persona no está registrada.")}
      end
    end)
  end

  def handle_event("historial_recurso", %{"codigo" => codigo, "ubicacion" => ubicacion}, socket) do
    con_sesion(socket, fn socket ->
      case Inventario.obtener(codigo, ubicacion) do
        {:ok, recurso} ->
          {:noreply, assign(socket, detalle: %{tipo: :recurso, registro: recurso}, accion: nil)}

        _ ->
          {:noreply, avisar(socket, :error, "El recurso no está registrado.")}
      end
    end)
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:datos_actualizados, _}, socket),
    do: con_sesion(socket, &{:noreply, recargar(&1)})

  def handle_info(:verificar_sesion, socket) do
    Process.send_after(self(), :verificar_sesion, 30_000)
    con_sesion(socket, &{:noreply, &1})
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp con_sesion(socket, funcion) do
    case SesionesWeb.obtener(socket.assigns.token) do
      {:ok, sesion} -> funcion.(assign(socket, sesion: sesion, usuario: sesion.usuario))
      _ -> {:noreply, redirect(socket, to: "/acceso")}
    end
  end

  defp recargar(socket) do
    datos = Presentacion.cargar(socket.assigns.usuario)

    assign(socket,
      datos: datos,
      coincidencias: Mascota.coincidencias(datos.mascotas),
      actualizado: Calendar.strftime(NaiveDateTime.local_now(), "%H:%M")
    )
  end

  defp avisar(socket, tipo, texto), do: assign(socket, :aviso, %{tipo: tipo, texto: texto})
  defp acciones(seccion, usuario), do: Operaciones.permitidas(seccion, usuario.tipo)
  defp permite?(usuario, comando), do: Permisos.permitido?(usuario.tipo, comando)
  defp ruta("inicio"), do: "/"
  defp ruta(id), do: "/panel/" <> id
  defp afectados(zonas), do: Enum.reduce(zonas, 0, &(Zona.acumulado(&1) + &2))
end
