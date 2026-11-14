defmodule EmergenciasWeb.AccesoLive do
  use EmergenciasWeb, :live_view

  @impl true
  def mount(_, session, socket) do
    socket = assign(socket, page_title: "Bienvenido", registro: false)

    case Emergencias.SesionesWeb.obtener(session["token"]) do
      {:ok, _} -> {:ok, redirect(socket, to: "/")}
      _ -> {:ok, socket}
    end
  end

  @impl true
  def handle_event("modo", %{"valor" => valor}, socket),
    do: {:noreply, assign(socket, :registro, valor == "registro")}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="access-page">
      <section class="access-story">
        <a href="/acceso" class="brand"><.marca /><span>NEXO<span class="brand-period">.</span></span></a>
        <div class="access-story-content">
          <span class="eyebrow light"><span class="status-dot"></span> CONECTADOS PARA RESPONDER</span>
          <h1>La ayuda empieza<br />con una <em>conexión.</em></h1>
          <p>
            Personas, recursos y lugares. Una misma red para acompañarnos cuando más lo necesitamos.
          </p>
          <div class="access-network" aria-hidden="true">
            <svg viewBox="0 0 480 250" fill="none">
              <path
                d="M60 140 165 62 270 135 415 70M60 140l125 65 85-70 110 75M165 62l20 143M270 135l-5-105M415 70l-35 140"
                stroke="currentColor"
                stroke-opacity=".18"
                stroke-width="1.5"
                stroke-dasharray="5 5"
              />
              <circle cx="270" cy="135" r="45" stroke="currentColor" stroke-opacity=".10" /><circle
                cx="270"
                cy="135"
                r="65"
                stroke="currentColor"
                stroke-opacity=".06"
              />
              <circle cx="270" cy="135" r="28" fill="#d9edb0" />
              <path
                d="M258 135h24m-12-12v24"
                stroke="#173b35"
                stroke-width="2.5"
                stroke-linecap="round"
              />
              <g fill="#33574f" stroke="#6b8b76">
                <circle cx="60" cy="140" r="17" /><circle cx="165" cy="62" r="17" /><circle
                  cx="185"
                  cy="205"
                  r="17"
                /><circle cx="415" cy="70" r="17" /><circle cx="380" cy="210" r="17" />
              </g>
              <g fill="#d9edb0">
                <circle cx="60" cy="140" r="4" /><circle cx="165" cy="62" r="4" /><circle
                  cx="185"
                  cy="205"
                  r="4"
                /><circle cx="415" cy="70" r="4" /><circle cx="380" cy="210" r="4" /><circle
                  cx="265"
                  cy="30"
                  r="4"
                />
              </g>
            </svg>
            <span class="network-label label-one"><.icono nombre="home" /> Un lugar seguro</span>
            <span class="network-label label-two"><.icono nombre="heart" /> Ayuda que llega</span>
          </div>
          <div class="access-promises">
            <span><.icono nombre="link" /> Una red compartida</span><span><.icono nombre="pulse" />
            Cambios en tiempo real</span>
          </div>
        </div>
        <p class="access-caption">CENTRO DE COORDINACIÓN DE EMERGENCIAS <span>01 / CONECTAR</span></p>
      </section>
      <section class="access-form-side">
        <div class="access-top">
          <span class="availability"><span class="status-dot"></span> Red disponible</span><span class="academic-tag">Proyecto académico</span>
        </div>
        <div class="access-form-wrap">
          <span class="section-kicker">UN PUNTO DE ENCUENTRO</span>
          <h2>{if @registro, do: "Tu lugar en la red.", else: "Qué bueno tenerte aquí."}</h2>
          <p class="access-intro">
            {if @registro,
              do: "Crea tu acceso y empieza a conectar la ayuda.",
              else: "Ingresa al centro de coordinación. Hay mucho que podemos hacer juntos."}
          </p>
          <div class="access-tabs" role="group" aria-label="Tipo de acceso">
            <button
              type="button"
              class={!@registro && "active"}
              phx-click="modo"
              phx-value-valor="ingreso"
            >Ingresar</button>
            <button
              type="button"
              class={@registro && "active"}
              phx-click="modo"
              phx-value-valor="registro"
            >Crear acceso</button>
          </div>
          <div :if={Phoenix.Flash.get(@flash, :error)} class="inline-alert" role="alert">
            <.icono nombre="alert" />{Phoenix.Flash.get(@flash, :error)}
          </div>
          <.form
            :let={_f}
            for={%{}}
            as={:acceso}
            action="/sesion"
            method="post"
            id="form-acceso"
            class="access-form"
          >
            <div :if={@registro} class="form-field">
              <label for="nombre">Nombre completo</label><input
                id="nombre"
                name="acceso[nombre]"
                placeholder="¿Cómo te llamas?"
                autocomplete="name"
                required
                maxlength="120"
              />
            </div>
            <div class="form-field">
              <label for="usuario">Usuario</label><input
                id="usuario"
                name="acceso[usuario]"
                placeholder="Tu nombre de usuario"
                autocomplete="username"
                required
                maxlength="80"
              />
            </div>
            <div class="form-field">
              <label for="clave">Contraseña</label><input
                type="password"
                id="clave"
                name="acceso[clave]"
                placeholder="Al menos 4 caracteres"
                autocomplete={if @registro, do: "new-password", else: "current-password"}
                minlength="4"
                required
                maxlength="200"
              />
            </div>
            <div :if={@registro} class="form-row">
              <div class="form-field">
                <label for="tipo">Tu rol</label><select id="tipo" name="acceso[tipo]">
                  <option value="ciudadano">Ciudadano</option><option value="voluntario">
                    Voluntario
                  </option><option value="coordinador">Coordinador</option><option value="administrador">
                    Administrador
                  </option>
                </select>
              </div>
              <div class="form-field">
                <label for="zona-acceso">Zona principal <span>Opcional</span></label><input
                  id="zona-acceso"
                  name="acceso[zona]"
                  placeholder="Código de tu zona"
                  maxlength="80"
                />
              </div>
            </div>
            <button class="button button-primary access-submit" type="submit">{if @registro,
              do: "Crear acceso y conectar",
              else: "Entrar a NEXO"}<.icono nombre="arrow" /></button>
          </.form>
          <p class="access-note">
            <.icono nombre="shield" />Tus acciones se registran para mantener una coordinación clara y responsable.
          </p>
          <p :if={!@registro} class="access-first">
            ¿Primera vez? El sistema también puede crear tu acceso como ciudadano al ingresar.
          </p>
        </div>
        <footer class="access-footer">
          <span>Hecho para acompañarnos.</span><span>Programación III · 2026</span>
        </footer>
      </section>
    </main>
    """
  end
end
