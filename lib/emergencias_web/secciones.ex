defmodule EmergenciasWeb.Secciones do
  use Phoenix.Component
  import EmergenciasWeb.Componentes
  alias EmergenciasWeb.Presentacion, as: P

  def zonas(assigns) do
    assigns =
      assign(assigns, :registros, P.filtrar(assigns.datos.zonas, assigns.consulta, assigns.zona))

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> zonas en esta vista</span><span class="muted-note">Zona → sectores → puntos de atención</span>
    </div>
    <div class="zone-grid">
      <article :for={z <- @registros} class="zone-card panel" id={"zona-#{z.codigo}"}>
        <div class="zone-card-top">
          <span class={["zone-symbol", "tone-" <> P.tono(z.nivel)]}><.icono nombre="map" /></span><.insignia valor={
            z.nivel
          } />
        </div>
        <span class="record-id">{z.codigo}</span><h2>{z.nombre}</h2>
        <div class="zone-stats">
          <div><strong>{P.numero(Zona.acumulado(z))}</strong><span>personas afectadas</span></div><div>
            <strong>{length(z.hijos)}</strong><span>sectores</span>
          </div><div><strong>{Zona.estadisticas(z).puntos}</strong><span>puntos</span></div>
        </div>
        <div class="sector-list">
          <details :for={sector <- z.hijos} class="sector">
            <summary>
              <span><.icono nombre="chevron" />{sector.nombre}</span><small>{Zona.acumulado(sector)} afectados</small>
            </summary>
            <div class="sector-points">
              <span class="sector-code">{sector.codigo} · {P.etiqueta(sector.nivel)}</span>
              <p :for={punto <- sector.hijos}>
                <span class="tiny-dot green"></span><strong>{punto.nombre}</strong><span>{punto.afectados} afectados</span>
              </p>
              <p :if={sector.hijos == []} class="muted-note">Aún no hay puntos de atención.</p>
            </div>
          </details>
          <p :if={z.hijos == []} class="zone-no-sectors">Esta zona todavía no tiene sectores.</p>
        </div>
        <div class="zone-card-footer">
          <button
            :if={permite?(@usuario, :register_sector)}
            class="text-link"
            phx-click="abrir"
            phx-value-accion="register_sector"
            phx-value-zona={z.codigo}
          ><.icono nombre="plus" />Agregar sector</button>
          <button
            :if={permite?(@usuario, :register_point) and z.hijos != []}
            class="text-link"
            phx-click="abrir"
            phx-value-accion="register_point"
            phx-value-zona={z.codigo}
          >Nuevo punto<.icono nombre="arrow" /></button>
        </div>
      </article>
    </div>
    <.vacio
      :if={@registros == []}
      titulo="Conectemos el territorio"
      descripcion="Registra una zona para empezar a organizar sectores, recursos y lugares de atención. Si ya hay registros, revisa los filtros."
      icono="map"
    />
    """
  end

  def necesidades(assigns) do
    assigns =
      assign(
        assigns,
        :registros,
        P.filtrar(assigns.datos.necesidades, assigns.consulta, assigns.zona)
      )

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> solicitudes en esta vista</span><span class="muted-note"><span class="tiny-dot amber"></span>Ordenadas por prioridad y antigüedad</span>
    </div>
    <section :if={@registros != []} class="panel table-panel">
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Solicitud</th><th>Prioridad</th><th>Zona</th><th>Cobertura</th><th>Estado</th><th class="align-right">
                Acciones
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={n <- @registros} id={"necesidad-#{n.id}"}>
              <td>
                <div class="table-primary">
                  {P.etiqueta(n.tipo)}<span class="record-id">{n.id}</span>
                </div><p class="table-description" title={n.descripcion}>
                  {P.corto(n.descripcion, 55)}
                </p><small class="cell-caption">Reportó {n.responsable}</small>
              </td>
              <td><.insignia valor={n.prioridad} /></td><td>
                <span class="location-cell"><.icono nombre="map" />{n.zona}</span>
              </td>
              <td>
                <div class="coverage">
                  <span><strong>{Necesidad.total_asignado(n)}</strong> / {n.cantidad}</span><div class="progress">
                    <span style={"width: #{P.porcentaje(Necesidad.total_asignado(n), n.cantidad)}%"}></span>
                  </div>
                </div>
              </td>
              <td><.insignia valor={n.estado} /></td>
              <td>
                <div class="row-actions">
                  <button
                    :if={permite?(@usuario, :assign_resource) and n.estado == :pendiente}
                    class="button button-small button-secondary"
                    phx-click="abrir"
                    phx-value-accion="assign_resource"
                    phx-value-necesidad={n.id}
                  >Asignar<.icono nombre="arrow" /></button><button
                    :if={permite?(@usuario, :need_status) and n.estado not in [:atendida, :cancelada]}
                    class="icon-button"
                    title="Actualizar atención"
                    aria-label={"Actualizar #{n.id}"}
                    phx-click="abrir"
                    phx-value-accion="need_status"
                    phx-value-id={n.id}
                  ><.icono nombre="pulse" /></button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="table-footer">Las asignaciones se confirman según las existencias disponibles.</div>
    </section>
    <.vacio
      :if={@registros == []}
      titulo="La próxima respuesta empieza aquí"
      descripcion="Registra una solicitud de ayuda o ajusta los filtros para encontrarla."
      icono="heart"
    />
    """
  end

  def recursos(assigns) do
    registros = P.filtrar(assigns.datos.recursos, assigns.consulta, assigns.zona)
    totales = registros |> Enum.group_by(&{&1.categoria, &1.unidad}) |> Enum.sort()
    assigns = assign(assigns, registros: registros, totales: totales)

    ~H"""
    <div class="stock-summary">
      <article :for={{{categoria, unidad}, lista} <- Enum.take(@totales, 4)} class="stock-tile">
        <span class="stock-symbol"><.icono nombre="box" /></span><div>
          <span>{P.etiqueta(categoria)}</span><strong>{P.numero(
            Enum.reduce(lista, 0, &(&1.cantidad + &2))
          )}<small>{unidad}</small></strong>
        </div>
      </article>
    </div>
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> registros de inventario</span><span class="muted-note"><span class="tiny-dot amber"></span>Alerta de existencias: 20 unidades o menos</span>
    </div>
    <section :if={@registros != []} class="panel table-panel">
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Recurso</th><th>Disponibilidad</th><th>Ubicación</th><th>Zona</th><th class="align-right">
                Movimientos
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @registros}>
              <td>
                <div class="resource-name">
                  <span class="table-icon"><.icono nombre="box" /></span><div>
                    <strong>{r.nombre}</strong><span class="cell-caption">{r.codigo} · {P.etiqueta(
                      r.categoria
                    )}</span>
                  </div>
                </div>
              </td>
              <td>
                <div class="stock-value">
                  <strong>{P.numero(r.cantidad)}</strong><span>{r.unidad}</span><span
                    :if={r.cantidad <= 20}
                    class={["stock-alert", r.cantidad == 0 && "stock-empty"]}
                  >{if r.cantidad == 0, do: "Agotado", else: "Bajo"}</span>
                </div>
              </td>
              <td>{r.ubicacion}</td><td>
                <span class="location-cell"><.icono nombre="map" />{r.zona || "Sin asignar"}</span>
              </td>
              <td>
                <div class="row-actions">
                  <button
                    class="icon-button"
                    phx-click="historial_recurso"
                    phx-value-codigo={r.codigo}
                    phx-value-ubicacion={r.ubicacion}
                    title="Historial de movimientos"
                    aria-label={"Historial de #{r.codigo} en #{r.ubicacion}"}
                  ><.icono nombre="clock" /></button><button
                    :if={permite?(@usuario, :resource_in)}
                    class="icon-button"
                    phx-click="abrir"
                    phx-value-accion="resource_in"
                    phx-value-codigo={r.codigo}
                    phx-value-ubicacion={r.ubicacion}
                    title="Registrar entrada"
                    aria-label={"Registrar entrada de #{r.codigo}"}
                  ><.icono nombre="plus" /></button><button
                    :if={permite?(@usuario, :transfer_resource)}
                    class="icon-button"
                    phx-click="abrir"
                    phx-value-accion="transfer_resource"
                    phx-value-codigo={r.codigo}
                    phx-value-origen={r.ubicacion}
                    title="Transferir recurso"
                    aria-label={"Transferir #{r.codigo}"}
                  ><.icono nombre="arrow" /></button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div><div class="table-footer">
        Cada entrada, salida y transferencia conserva su historial.
      </div>
    </section>
    <.vacio
      :if={@registros == []}
      titulo="La ayuda necesita hacerse visible"
      descripcion="Registra los suministros disponibles y su ubicación para empezar a asignarlos."
      icono="box"
    />
    """
  end

  def personas(assigns) do
    assigns =
      assign(
        assigns,
        :registros,
        P.filtrar(assigns.datos.personas, assigns.consulta, assigns.zona)
      )

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> personas en esta vista</span><span class="muted-note">Busca también por documento, referencia o estado</span>
    </div>
    <section :if={@registros != []} class="panel table-panel">
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Persona</th><th>Documento / referencia</th><th>Zona</th><th>Estado</th><th class="align-right">
                Seguimiento
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={p <- @registros} id={"persona-#{p.documento}"}>
              <td>
                <div class="person-cell">
                  <span class="avatar avatar-light">{P.iniciales(p.nombre)}</span><div>
                    <strong>{p.nombre}</strong><span class="cell-caption">{p.edad} años</span>
                  </div>
                </div>
              </td><td class="mono">{p.documento}</td><td>
                <span class="location-cell"><.icono nombre="map" />{p.zona}</span>
              </td><td><.insignia valor={p.estado} /></td><td>
                <div class="row-actions">
                  <button
                    class="icon-button"
                    title="Historial de estados"
                    aria-label={"Historial de #{p.nombre}"}
                    phx-click="historial_persona"
                    phx-value-documento={p.documento}
                  ><.icono nombre="clock" /></button><button
                    :if={permite?(@usuario, :update_person) and p.estado != :reunificada}
                    class="button button-small button-secondary"
                    phx-click="abrir"
                    phx-value-accion="update_person"
                    phx-value-documento={p.documento}
                  >Actualizar</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div><div class="table-footer">
        Los cambios de estado se conservan para facilitar el seguimiento.
      </div>
    </section>
    <.vacio
      :if={@registros == []}
      titulo="Ayudemos a encontrarnos"
      descripcion="Registra información de una persona afectada para facilitar su ubicación y el contacto con su familia."
      icono="users"
    />
    """
  end

  def mensajes(assigns) do
    zonas = Map.new(assigns.datos.personas, &{&1.documento, &1.zona})

    registros =
      assigns.datos.mensajes
      |> Enum.map(&Map.put(Map.from_struct(&1), :zona, zonas[&1.destinatario]))
      |> P.filtrar(assigns.consulta, assigns.zona)
      |> Enum.reverse()

    assigns = assign(assigns, :registros, registros)

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> mensajes en esta vista</span><span class="muted-note">El filtro de zona usa la zona de la persona destinataria</span>
    </div>
    <div class="message-grid">
      <article
        :for={m <- @registros}
        class={["panel message-card", m.estado == :pendiente && "message-pending"]}
        id={"mensaje-#{m.id}"}
      >
        <div class="message-top">
          <span class="message-envelope"><.icono nombre="message" /></span><.insignia valor={m.estado} />
        </div>
        <span class="record-id">MENSAJE #{m.id}</span><h2>Para {m.destinatario}</h2><p class="message-content">
          {m.contenido}
        </p>
        <div class="message-meta">
          <span class="avatar avatar-tiny">{P.iniciales(m.remitente)}</span><div>
            <strong>{m.remitente}</strong><time>{String.replace(m.fecha, "T", " · ")}</time>
          </div>
        </div>
        <button
          :if={permite?(@usuario, :mark_message)}
          class="message-action"
          phx-click="abrir"
          phx-value-accion="mark_message"
          phx-value-id={m.id}
          phx-value-estado={if m.estado == :pendiente, do: "entregado", else: "pendiente"}
        >{if m.estado == :pendiente, do: "Confirmar entrega", else: "Volver a pendiente"}<.icono nombre="arrow" /></button>
      </article>
    </div>
    <.vacio
      :if={@registros == []}
      titulo="Una conexión puede traer tranquilidad"
      descripcion="Deja un mensaje para una persona o familia usando su documento o referencia."
      icono="message"
    />
    """
  end

  def mascotas(assigns) do
    registros = P.filtrar(assigns.datos.mascotas, assigns.consulta, assigns.zona)
    ids = MapSet.new(registros, & &1.id)

    coincidencias =
      Enum.filter(
        assigns.coincidencias,
        &(MapSet.member?(ids, &1.perdida) or MapSet.member?(ids, &1.encontrada))
      )

    assigns = assign(assigns, registros: registros, coincidencias: coincidencias)

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> reportes en esta vista</span><span class="muted-note">Cada reencuentro importa</span>
    </div>
    <div class="pet-grid">
      <article :for={m <- @registros} class="panel pet-card" id={"mascota-#{m.id}"}>
        <div class={["pet-illustration", m.tipo == :encontrada && "pet-found"]}>
          <.animal especie={m.especie} /><span class="pet-type">{P.etiqueta(m.tipo)}</span><span class="pet-reference">{m.id}</span>
        </div>
        <div class="pet-body">
          <div class="pet-heading">
            <h2>{if m.nombre == "desconocido", do: "Por reconocer", else: m.nombre}</h2><.insignia valor={
              m.estado
            } />
          </div>
          <p class="pet-traits">
            {P.etiqueta(m.especie)}<span>·</span>{m.color}<span>·</span>{P.etiqueta(m.tamano)}
          </p>
          <p class="pet-description">
            {if m.caracteristicas == "",
              do: "Sin señas particulares registradas.",
              else: m.caracteristicas}
          </p>
          <div class="pet-footer">
            <span><.icono nombre="map" />{m.zona}</span><span>Contacto: {m.contacto}</span>
          </div>
          <p :if={m.coincidencia} class="pet-reunion">
            <.icono nombre="check" />Reencuentro vinculado con {m.coincidencia}
          </p>
        </div>
      </article>
    </div>
    <.vacio
      :if={@registros == []}
      titulo="También los estamos buscando a ellos"
      descripcion="Reporta una mascota perdida o encontrada y conecta la información para facilitar su reencuentro."
      icono="paw"
    />
    <section :if={@coincidencias != []} class="panel matches-panel">
      <div class="panel-heading">
        <div>
          <span class="panel-kicker">POSIBLES REENCUENTROS</span><h2>Hay algo en común</h2>
        </div><span class="count-chip">{length(@coincidencias)} coincidencias</span>
      </div>
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Reporte de pérdida</th><th>Reporte de hallazgo</th><th>Similitud</th><th class="align-right">
                Confirmación
              </th>
            </tr>
          </thead><tbody>
            <tr :for={par <- @coincidencias}>
              <td>{par.perdida}</td><td>{par.encontrada}</td><td>
                <div class="similarity">
                  <div class="progress"><span style={"width: #{par.puntaje}%"}></span></div><strong>{par.puntaje} / 100</strong>
                </div>
              </td><td class="align-right">
                <button
                  :if={permite?(@usuario, :confirm_match)}
                  class="button button-small button-secondary"
                  phx-click="abrir"
                  phx-value-accion="confirm_match"
                  phx-value-perdida={par.perdida}
                  phx-value-encontrada={par.encontrada}
                >Confirmar reencuentro<.icono nombre="arrow" /></button><span
                  :if={!permite?(@usuario, :confirm_match)}
                  class="muted-note"
                >Requiere coordinador</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  def albergues(assigns) do
    registros =
      assigns.datos.albergues
      |> P.filtrar(assigns.consulta, assigns.zona)
      |> Enum.sort_by(& &1.porcentaje, :desc)

    assigns = assign(assigns, :registros, registros)

    ~H"""
    <div class="section-summary">
      <span><strong>{length(@registros)}</strong> albergues en esta vista</span><span class="muted-note">De mayor a menor ocupación</span>
    </div>
    <div class="shelter-grid">
      <article :for={a <- @registros} class="panel shelter-card" id={"albergue-#{a.codigo}"}>
        <div class="shelter-card-top">
          <span class="shelter-symbol"><.icono nombre="home" /></span><span class={[
            "badge",
            if(a.cupos == 0, do: "badge-coral", else: "badge-green")
          ]}><span class="badge-dot"></span>{if a.cupos == 0,
            do: "Sin cupos",
            else: "Con disponibilidad"}</span>
        </div>
        <span class="record-id">{a.codigo}</span><h2>{a.nombre}</h2><p class="location-cell">
          <.icono nombre="map" />{a.zona}
        </p>
        <div class="shelter-capacity">
          <div><strong>{a.cupos}</strong><span>cupos disponibles</span></div><span class="capacity-total">de {a.capacidad}</span>
        </div>
        <div class={["progress shelter-progress", a.porcentaje >= 85 && "progress-amber"]}>
          <span style={"width: #{a.porcentaje}%"}></span>
        </div>
        <div class="occupancy-caption">
          <span>{a.ocupacion} personas alojadas</span><strong>{round(a.porcentaje)}% de ocupación</strong>
        </div>
        <div class="shelter-links">
          <span><.icono nombre="box" />{length(a.recursos)} recursos vinculados</span><span><.icono nombre="heart" />{length(
            a.necesidades
          )} necesidades</span>
        </div>
        <details
          :if={a.ocupantes != [] or a.recursos != [] or a.necesidades != []}
          class="shelter-details"
        >
          <summary>Ver personas y vínculos<.icono nombre="chevron" /></summary><div>
            <p :if={a.ocupantes != []}>
              <strong>Documentos alojados</strong>{Enum.join(a.ocupantes, ", ")}
            </p><p :if={a.recursos != []}><strong>Recursos</strong>{Enum.join(a.recursos, ", ")}</p><p :if={
              a.necesidades != []
            }>
              <strong>Necesidades</strong>{Enum.join(a.necesidades, ", ")}
            </p>
          </div>
        </details>
        <div class="shelter-card-actions">
          <button
            :if={permite?(@usuario, :register_entry)}
            class="button button-secondary"
            disabled={a.cupos == 0}
            phx-click="abrir"
            phx-value-accion="register_entry"
            phx-value-codigo={a.codigo}
          ><.icono nombre="plus" />Ingreso</button><button
            :if={permite?(@usuario, :register_exit)}
            class="button button-subtle"
            disabled={a.ocupacion == 0}
            phx-click="abrir"
            phx-value-accion="register_exit"
            phx-value-codigo={a.codigo}
          >Salida<.icono nombre="arrow" /></button>
        </div>
      </article>
    </div>
    <.vacio
      :if={@registros == []}
      titulo="Un espacio para estar a salvo"
      descripcion="Agrega los albergues de tu red para coordinar cupos, ingresos y recursos."
      icono="home"
    />
    """
  end

  def actividad(assigns) do
    ~H"""
    <div class="section-summary">
      <span>{if @usuario.tipo == :administrador,
        do: "Actividad de toda la red",
        else: "Tus acciones en la red"}</span><span class="muted-note">Hasta 40 acciones recientes</span>
    </div>
    <div class={["activity-layout", @usuario.tipo != :administrador && "activity-single"]}>
      <section class="panel activity-panel">
        <div class="panel-heading">
          <div>
            <span class="panel-kicker">EL PULSO DE LA COORDINACIÓN</span><h2>
              Acciones que dejan huella
            </h2>
          </div><.icono nombre="pulse" />
        </div>
        <div class="activity-list">
          <article :for={{usuario, fecha, comando} <- @datos.actividad} class="activity-item">
            <span class="activity-symbol"><.icono nombre="pulse" /></span><div>
              <strong>{P.accion_actividad(comando)}</strong><p>{usuario}<span> · </span>{fecha}</p>
            </div>
          </article>
        </div>
        <.vacio
          :if={@datos.actividad == []}
          titulo="Todo empieza con una acción"
          descripcion="Tu actividad aparecerá aquí conforme participes en la coordinación."
          icono="pulse"
        />
      </section>
      <section :if={@usuario.tipo == :administrador} class="panel users-panel">
        <div class="panel-heading">
          <div>
            <span class="panel-kicker">QUIÉNES HACEN POSIBLE LA RED</span><h2>Equipo conectado</h2>
          </div><span class="count-chip">{length(@datos.usuarios)}</span>
        </div>
        <div class="team-list">
          <article :for={u <- @datos.usuarios} class="team-member">
            <span class="avatar avatar-light">{P.iniciales(u.nombre)}</span><div>
              <strong>{u.nombre}</strong><p>{u.usuario} · {P.etiqueta(u.tipo)}</p><span>{u.zona}</span>
            </div><span
              class={["presence-dot", u.conectado && "online"]}
              title={if u.conectado, do: "Conectado", else: "Desconectado"}
            ></span>
          </article>
        </div>
      </section>
    </div>
    """
  end

  attr :especie, :string, required: true

  def animal(assigns) do
    assigns = assign(assigns, :gato, Validacion.coincide?(assigns.especie, "gato"))

    ~H"""
    <svg class="animal-art" viewBox="0 0 180 130" fill="none" aria-hidden="true">
      <ellipse cx="90" cy="116" rx="55" ry="7" fill="currentColor" opacity=".06" />
      <path
        :if={!@gato}
        d="M50 42c-30-15-32 42-12 47l19-18m73-29c30-15 32 42 12 47l-19-18"
        fill="#c9b18b"
        stroke="#6c6252"
        stroke-width="2"
      />
      <path
        :if={@gato}
        d="m48 54-4-39 37 26m51 13 4-39-37 26"
        fill="#c9b18b"
        stroke="#6c6252"
        stroke-width="2"
        stroke-linejoin="round"
      />
      <path
        d="M46 70c0-29 19-45 44-45s44 16 44 45c0 26-17 44-44 44S46 96 46 70Z"
        fill="#e0cbaa"
        stroke="#6c6252"
        stroke-width="2"
      />
      <path d="M70 91c0-12 8-22 20-22s20 10 20 22c0 12-40 12-40 0Z" fill="#f7eedb" />
      <path d="M69 64v6m42-6v6" stroke="#4c4b42" stroke-width="5" stroke-linecap="round" />
      <path d="m84 83 6 5 6-5c0-6-12-6-12 0Z" fill="#6c6252" />
      <path
        d="M90 88v7m0 0c-4 5-9 1-9 1m9-1c4 5 9 1 9 1"
        stroke="#6c6252"
        stroke-width="1.7"
        stroke-linecap="round"
      />
      <path
        :if={@gato}
        d="m63 84-25-4m25 11-26 3m80-10 25-4m-25 11 26 3"
        stroke="#6c6252"
        stroke-width="1.4"
        stroke-linecap="round"
      />
      <path d="M63 109c18 7 36 7 54 0" stroke="#66816c" stroke-width="5" stroke-linecap="round" />
      <circle cx="90" cy="115" r="5" fill="#c5a15c" />
    </svg>
    """
  end

  defp permite?(usuario, comando), do: Permisos.permitido?(usuario.tipo, comando)
end
