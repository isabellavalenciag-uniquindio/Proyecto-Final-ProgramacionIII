defmodule EmergenciasWeb.Componentes do
  use Phoenix.Component
  alias EmergenciasWeb.Presentacion

  @iconos %{
    "grid" => ["M3 3h7v7H3z", "M14 3h7v7h-7z", "M3 14h7v7H3z", "M14 14h7v7h-7z"],
    "map" => ["m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Z", "M9 3v15", "M15 6v15"],
    "heart" => [
      "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z",
      "M7 12h3l2-4 2 8 2-4h3"
    ],
    "box" => ["m12 3 9 5v9l-9 5-9-5V8l9-5Z", "m3 8 9 5 9-5", "M12 13v9", "m7.5 5.5 9 5"],
    "users" => [
      "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2",
      "M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8",
      "M22 21v-2a4 4 0 0 0-3-3.9",
      "M16 3.1a4 4 0 0 1 0 7.8"
    ],
    "message" => [
      "M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8A8.5 8.5 0 0 1 8.7 3.9a8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z",
      "M8 10h8",
      "M8 14h5"
    ],
    "home" => ["m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10Z", "M9 21v-8h6v8"],
    "paw" => [
      "M8 14c1-4 7-4 8 0 4 2 3 7-1 6-2-1-4-1-6 0-4 1-5-4-1-6Z",
      "M5 6c-3 0-3 5 0 5s3-5 0-5",
      "M10 2c-3 0-3 6 0 6s3-6 0-6",
      "M16 3c-3 0-3 6 0 6s3-6 0-6",
      "M21 8c-3-1-4 4-2 5s4-4 2-5"
    ],
    "pulse" => ["M2 12h5l3-9 4 18 3-9h5"],
    "plus" => ["M12 5v14", "M5 12h14"],
    "arrow" => ["M5 12h14", "m13 6 6 6-6 6"],
    "chevron" => ["m9 5 7 7-7 7"],
    "search" => ["M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15", "m16 16 5 5"],
    "close" => ["m6 6 12 12", "M18 6 6 18"],
    "check" => ["m5 12 4 4L19 6"],
    "logout" => ["M9 21H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5", "M9 12h12", "m17 8 4 4-4 4"],
    "clock" => ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18", "M12 7v5l3 2"],
    "shield" => ["m12 3 9 4v6c0 5-9 9-9 9s-9-4-9-9V7l9-4Z", "m8 12 3 3 5-6"],
    "sun" => [
      "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8",
      "M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"
    ],
    "menu" => ["M4 6h16M4 12h16M4 18h16"],
    "link" => ["m10 13 4-4", "M8 16H6a5 5 0 0 1 0-10h4", "M14 6h4a5 5 0 0 1 0 10h-2"],
    "alert" => ["m12 3 10 18H2L12 3Z", "M12 9v4", "M12 17h.01"],
    "spark" => ["m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"]
  }

  attr :nombre, :string, required: true
  attr :class, :string, default: ""

  def icono(assigns) do
    assigns = assign(assigns, :trazos, Map.get(@iconos, assigns.nombre, @iconos["grid"]))

    ~H"""
    <svg
      class={["icon", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.65"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path :for={trazo <- @trazos} d={trazo} />
    </svg>
    """
  end

  attr :class, :string, default: ""

  def marca(assigns) do
    ~H"""
    <span class={["brand-mark", @class]} aria-hidden="true">
      <svg viewBox="0 0 32 32" fill="none"><path
        d="M7 25V7h6l12 18V7h-6v18L7 7"
        stroke="currentColor"
        stroke-width="3.2"
        stroke-linejoin="round"
      /></svg>
    </span>
    """
  end

  attr :valor, :any, required: true

  def insignia(assigns) do
    ~H"""
    <span class={["badge", "badge-" <> Presentacion.tono(@valor)]}><span class="badge-dot"></span>{Presentacion.etiqueta(
      @valor
    )}</span>
    """
  end

  attr :titulo, :string, required: true
  attr :valor, :any, required: true
  attr :detalle, :string, default: ""
  attr :icono, :string, required: true
  attr :tono, :string, default: "green"
  attr :unidad, :string, default: ""

  def metrica(assigns) do
    ~H"""
    <article class={["metric", "metric-" <> @tono]}>
      <div class="metric-top">
        <span>{@titulo}</span><span class="metric-icon"><.icono nombre={@icono} /></span>
      </div>
      <div class="metric-value">{Presentacion.numero(@valor)}<span>{@unidad}</span></div>
      <p>{@detalle}</p>
    </article>
    """
  end

  attr :titulo, :string, required: true
  attr :descripcion, :string, required: true
  attr :icono, :string, default: "spark"
  slot :inner_block

  def vacio(assigns) do
    ~H"""
    <div class="empty-state">
      <span class="empty-icon"><.icono nombre={@icono} /></span>
      <h3>{@titulo}</h3><p>{@descripcion}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :campo, :map, required: true
  attr :valores, :map, required: true
  attr :datos, :map, required: true
  attr :errores, :map, default: %{}

  def campo(assigns) do
    assigns =
      assign(assigns,
        valor: Map.get(assigns.valores, assigns.campo.clave, ""),
        opciones:
          EmergenciasWeb.Operaciones.opciones(assigns.campo.tipo, assigns.datos, assigns.valores)
      )

    ~H"""
    <div class={[
      "form-field",
      @campo.tipo == "textarea" && "field-wide",
      @errores[@campo.clave] && "field-error"
    ]}>
      <label for={"campo-#{@campo.clave}"}>{@campo.etiqueta}<span :if={!@campo.requerido}>Opcional</span></label>
      <select
        :if={is_atom(@campo.tipo)}
        id={"campo-#{@campo.clave}"}
        name={"operacion[#{@campo.clave}]"}
        required={@campo.requerido}
      >
        <option value="" selected={@valor == ""}>
          {if @campo.requerido, do: "Selecciona una opción", else: "Seleccionar si corresponde"}
        </option>
        <option :for={{valor, texto} <- @opciones} value={valor} selected={@valor == valor}>
          {texto}
        </option>
      </select>
      <textarea
        :if={@campo.tipo == "textarea"}
        id={"campo-#{@campo.clave}"}
        name={"operacion[#{@campo.clave}]"}
        rows="3"
        placeholder={@campo.ejemplo}
        required={@campo.requerido}
        maxlength={@campo.max}
        phx-debounce="300"
      >{@valor}</textarea>
      <input
        :if={is_binary(@campo.tipo) and @campo.tipo != "textarea"}
        type={@campo.tipo}
        id={"campo-#{@campo.clave}"}
        name={"operacion[#{@campo.clave}]"}
        value={@valor}
        placeholder={@campo.ejemplo}
        required={@campo.requerido}
        min={if @campo.tipo == "number", do: @campo.min}
        phx-debounce="300"
      />
      <span :if={@errores[@campo.clave]} class="field-message" role="alert">{@errores[@campo.clave]}</span>
    </div>
    """
  end
end
