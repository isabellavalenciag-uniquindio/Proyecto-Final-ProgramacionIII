defmodule EmergenciasWeb.Operaciones do
  @moduledoc "Catálogo de formularios y adaptación de datos a las operaciones compartidas."

  def todas do
    [
      a(
        :register_zone,
        "Registrar zona",
        "zonas",
        "Un nuevo punto de partida para coordinar la ayuda.",
        [
          c("codigo", "Código", "text", ejemplo: "Z-NORTE"),
          c("nombre", "Nombre de la zona", "text", ejemplo: "Zona Norte"),
          c("nivel", "Nivel de afectación", :niveles, defecto: "alto"),
          c("afectados", "Personas afectadas estimadas", "number", defecto: "0", min: 0)
        ]
      ),
      a(:register_sector, "Agregar sector", "zonas", "Organiza la atención dentro de una zona.", [
        c("zona", "Zona", :zonas),
        c("codigo", "Código del sector", "text"),
        c("nombre", "Nombre", "text"),
        c("nivel", "Afectación", :niveles, defecto: "alto"),
        c("afectados", "Personas afectadas", "number", defecto: "0", min: 0)
      ]),
      a(
        :register_point,
        "Agregar punto de atención",
        "zonas",
        "Conecta un punto de atención con su sector.",
        [
          c("zona", "Zona", :zonas),
          c("sector", "Sector", :sectores),
          c("codigo", "Código del punto", "text"),
          c("nombre", "Nombre", "text"),
          c("afectados", "Personas afectadas", "number", defecto: "0", min: 0)
        ]
      ),
      a(
        :register_need,
        "Solicitar ayuda",
        "necesidades",
        "Cada solicitud conecta una necesidad con una respuesta.",
        [
          c("tipo", "Tipo de ayuda", :tipos_necesidad, defecto: "agua"),
          c("cantidad", "Cantidad requerida", "number", defecto: "1"),
          c("prioridad", "Prioridad", :prioridades, defecto: "alta"),
          c("zona", "Zona", :zonas),
          c("descripcion", "Describe la necesidad", "textarea",
            requerido: false,
            ejemplo: "¿Qué se necesita y dónde?"
          )
        ]
      ),
      a(
        :assign_resource,
        "Asignar recursos",
        "necesidades",
        "El inventario se verifica antes de confirmar la asignación.",
        [
          c("necesidad", "Necesidad pendiente", :necesidades),
          c("recurso", "Recurso", :recursos),
          c("cantidad", "Cantidad a asignar", "number", defecto: "1")
        ]
      ),
      a(
        :need_status,
        "Actualizar atención",
        "necesidades",
        "Registra el avance de una solicitud.",
        [
          c("id", "Necesidad", :todas_necesidades),
          c("estado", "Nuevo estado", :estados_necesidad)
        ]
      ),
      a(
        :cancel_need,
        "Cancelar necesidad",
        "necesidades",
        "Los recursos reservados vuelven al inventario.",
        [
          c("id", "Necesidad", :necesidades_abiertas)
        ]
      ),
      a(
        :register_resource,
        "Registrar recurso",
        "recursos",
        "Haz visible la ayuda disponible en tu red.",
        [
          c("codigo", "Código", "text", ejemplo: "R-AGUA"),
          c("nombre", "Nombre", "text", ejemplo: "Agua"),
          c("cantidad", "Existencias iniciales", "number", defecto: "0", min: 0),
          c("unidad", "Unidad de medida", "text", ejemplo: "litros"),
          c("ubicacion", "Centro o ubicación", "text", ejemplo: "Centro de acopio norte"),
          c("categoria", "Categoría", :tipos_necesidad, defecto: "agua"),
          c("zona", "Zona", :zonas)
        ]
      ),
      a(
        :resource_in,
        "Registrar entrada",
        "recursos",
        "Suma nuevas donaciones o suministros.",
        movimiento()
      ),
      a(
        :resource_out,
        "Registrar salida",
        "recursos",
        "Registra una entrega y conserva su movimiento.",
        movimiento()
      ),
      a(
        :transfer_resource,
        "Transferir recursos",
        "recursos",
        "Mueve suministros entre centros de apoyo.",
        [
          c("codigo", "Recurso", :recursos),
          c("origen", "Ubicación de origen", :ubicaciones),
          c("destino", "Ubicación de destino", "text", ejemplo: "Centro de apoyo sur"),
          c("cantidad", "Cantidad", "number", defecto: "1"),
          c("zona_destino", "Zona del destino", :zonas, requerido: false)
        ]
      ),
      a(
        :report_person,
        "Registrar persona",
        "personas",
        "La información correcta ayuda a reunir a las familias.",
        [
          c("documento", "Documento o referencia", "text"),
          c("nombre", "Nombre completo", "text"),
          c("zona", "Zona", :zonas),
          c("estado", "Estado", :estados_persona, defecto: "reportada"),
          c("edad", "Edad", "number", defecto: "0", min: 0)
        ]
      ),
      a(
        :update_person,
        "Actualizar persona",
        "personas",
        "Cada cambio se conserva en el historial.",
        [
          c("documento", "Persona", :personas),
          c("estado", "Nuevo estado", :estados_persona)
        ]
      ),
      a(
        :send_family_message,
        "Enviar mensaje",
        "mensajes",
        "Un mensaje puede hacer toda la diferencia.",
        [
          c("documento", "Documento o referencia del destinatario", "text"),
          c("contenido", "Tu mensaje", "textarea",
            ejemplo: "Estoy bien. Me encuentro en…",
            max: 500
          )
        ]
      ),
      a(
        :mark_message,
        "Actualizar mensaje",
        "mensajes",
        "Confirma la entrega o vuelve a dejarlo pendiente.",
        [
          c("id", "Mensaje", :mensajes),
          c("estado", "Estado", :estados_mensaje, defecto: "entregado")
        ]
      ),
      a(
        :report_pet,
        "Reportar mascota",
        "mascotas",
        "Ayudemos a que también encuentren el camino a casa.",
        [
          c("tipo", "Tipo de reporte", :tipos_reporte, defecto: "lost"),
          c("especie", "Especie", "text", ejemplo: "perro"),
          c("nombre", "Nombre, si se conoce", "text", requerido: false),
          c("color", "Color", "text", ejemplo: "Negro y blanco"),
          c("tamano", "Tamaño", :tamanos, defecto: "mediano"),
          c("zona", "Zona", :zonas),
          c("contacto", "Contacto", "text"),
          c("caracteristicas", "Señas particulares", "textarea",
            requerido: false,
            ejemplo: "Collar, manchas, características…"
          )
        ]
      ),
      a(
        :match_pets,
        "Buscar coincidencias",
        "mascotas",
        "Compara especie, color, zona, tamaño y señas particulares.",
        []
      ),
      a(
        :confirm_match,
        "Confirmar reencuentro",
        "mascotas",
        "Cierra los dos reportes que corresponden a la misma mascota.",
        [
          c("perdida", "Reporte de mascota perdida", :perdidas),
          c("encontrada", "Reporte de mascota encontrada", :encontradas)
        ]
      ),
      a(
        :register_shelter,
        "Registrar albergue",
        "albergues",
        "Un espacio seguro para empezar a recuperarse.",
        [
          c("codigo", "Código", "text", ejemplo: "A-NORTE"),
          c("nombre", "Nombre", "text"),
          c("zona", "Zona", :zonas),
          c("capacidad", "Capacidad máxima", "number", defecto: "50")
        ]
      ),
      a(
        :register_entry,
        "Registrar ingreso",
        "albergues",
        "El sistema comprueba los cupos y evita ingresos duplicados.",
        [
          c("codigo", "Albergue", :albergues),
          c("documento", "Documento o referencia", "text")
        ]
      ),
      a(
        :register_exit,
        "Registrar salida",
        "albergues",
        "Libera el cupo y actualiza el estado de la persona.",
        [
          c("codigo", "Albergue", :albergues),
          c("documento", "Persona alojada", :ocupantes)
        ]
      ),
      a(
        :shelter_link,
        "Vincular ayuda",
        "albergues",
        "Relaciona un recurso o una necesidad con el albergue.",
        [
          c("codigo", "Albergue", :albergues),
          c("tipo", "Qué deseas vincular", :tipos_vinculo, defecto: "recurso"),
          c("id", "Código del recurso o ID de la necesidad", "text")
        ]
      )
    ]
  end

  def buscar(id), do: Enum.find(todas(), &(&1.id == id))

  def permitidas(seccion, tipo),
    do: Enum.filter(todas(), &(&1.seccion == seccion and Permisos.permitido?(tipo, &1.comando)))

  def iniciales(accion), do: Map.new(accion.campos, &{&1.clave, &1.defecto})

  def ejecutar(id, params, sesion) when is_map(params) do
    case buscar(id) do
      nil ->
        {:error, "La operación no existe.", sesion, %{}}

      accion ->
        errores =
          Enum.reduce(accion.campos, %{}, fn campo, acc ->
            valor = Map.get(params, campo.clave, campo.defecto)

            if not is_binary(valor) or (campo.requerido and String.trim(valor) == ""),
              do: Map.put(acc, campo.clave, "Completa este campo."),
              else: acc
          end)

        if map_size(errores) > 0 do
          {:error, "Revisa los campos señalados.", sesion, errores}
        else
          args = Enum.map(accion.campos, &Map.get(params, &1.clave, &1.defecto))

          args =
            if id == "transfer_resource" and List.last(args) == "",
              do: Enum.drop(args, -1),
              else: args

          case Comandos.ejecutar_operacion(accion.comando, args, sesion) do
            {:ok, texto, nueva} -> {:ok, texto, nueva}
            {_, texto, nueva} -> {:error, texto, nueva, %{}}
          end
        end
    end
  end

  def ejecutar(_, _, sesion),
    do: {:error, "Los datos del formulario no son válidos.", sesion, %{}}

  def opciones(tipo, datos, params) do
    case tipo do
      :zonas ->
        Enum.map(datos.zonas, &{&1.codigo, &1.nombre})

      :sectores ->
        datos.zonas
        |> Enum.filter(&(Map.get(params, "zona", "") in ["", &1.codigo]))
        |> Enum.flat_map(fn z ->
          Enum.map(z.hijos, &{&1.codigo, "#{z.nombre} · #{&1.nombre}"})
        end)

      :necesidades ->
        necesidades(datos, &(&1.estado == :pendiente))

      :necesidades_abiertas ->
        necesidades(datos, &(&1.estado not in [:atendida, :cancelada]))

      :todas_necesidades ->
        necesidades(datos, fn _ -> true end)

      :recursos ->
        datos.recursos
        |> Enum.uniq_by(& &1.codigo)
        |> Enum.map(&{&1.codigo, "#{&1.codigo} · #{&1.nombre}"})

      :ubicaciones ->
        datos.recursos |> Enum.map(&{&1.ubicacion, &1.ubicacion}) |> Enum.uniq()

      :personas ->
        Enum.map(datos.personas, &{&1.documento, "#{&1.nombre} · #{&1.documento}"})

      :albergues ->
        Enum.map(datos.albergues, &{&1.codigo, "#{&1.nombre} · #{&1.cupos} cupos"})

      :ocupantes ->
        datos.albergues
        |> Enum.filter(&(Map.get(params, "codigo", "") in ["", &1.codigo]))
        |> Enum.flat_map(fn a -> Enum.map(a.ocupantes, &{&1, "#{&1} · #{a.nombre}"}) end)

      :mensajes ->
        Enum.map(datos.mensajes, &{to_string(&1.id), "##{&1.id} · Para #{&1.destinatario}"})

      :perdidas ->
        mascotas(datos, :perdida)

      :encontradas ->
        mascotas(datos, :encontrada)

      :niveles ->
        etiquetas([:critico, :alto, :medio, :bajo])

      :prioridades ->
        etiquetas(Necesidad.prioridades())

      :tipos_necesidad ->
        etiquetas(Necesidad.tipos())

      :estados_necesidad ->
        etiquetas(Necesidad.estados())

      :estados_persona ->
        etiquetas(Persona.estados())

      :estados_mensaje ->
        etiquetas([:pendiente, :entregado])

      :tipos_reporte ->
        [{"lost", "Perdida"}, {"found", "Encontrada"}]

      :tamanos ->
        [{"pequeno", "Pequeño"}, {"mediano", "Mediano"}, {"grande", "Grande"}]

      :tipos_vinculo ->
        [{"recurso", "Recurso"}, {"necesidad", "Necesidad"}]

      _ ->
        []
    end
  end

  defp etiquetas(lista),
    do: Enum.map(lista, &{to_string(&1), EmergenciasWeb.Presentacion.etiqueta(&1)})

  defp necesidades(datos, filtro),
    do:
      datos.necesidades
      |> Enum.filter(filtro)
      |> Enum.map(
        &{&1.id, "#{&1.id} · #{EmergenciasWeb.Presentacion.etiqueta(&1.tipo)} · #{&1.zona}"}
      )

  defp mascotas(datos, tipo),
    do:
      datos.mascotas
      |> Enum.filter(&(&1.tipo == tipo and &1.estado != :resuelta))
      |> Enum.map(&{&1.id, "#{&1.id} · #{&1.nombre} · #{&1.especie}"})

  defp a(comando, titulo, seccion, descripcion, campos),
    do: %{
      id: to_string(comando),
      comando: comando,
      titulo: titulo,
      seccion: seccion,
      descripcion: descripcion,
      campos: campos
    }

  defp c(clave, etiqueta, tipo, opts \\ []) do
    %{
      clave: clave,
      etiqueta: etiqueta,
      tipo: tipo,
      requerido: Keyword.get(opts, :requerido, true),
      defecto: Keyword.get(opts, :defecto, ""),
      ejemplo: Keyword.get(opts, :ejemplo, ""),
      min: Keyword.get(opts, :min, 1),
      max: Keyword.get(opts, :max)
    }
  end

  defp movimiento,
    do: [
      c("codigo", "Recurso", :recursos),
      c("ubicacion", "Ubicación", :ubicaciones),
      c("cantidad", "Cantidad", "number", defecto: "1")
    ]
end
