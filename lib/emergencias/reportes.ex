defmodule Reportes do
  @moduledoc """
  Consultas y reportes generales. Reúne datos de varios procesos y los
  convierte en mapas (para usarlos desde código) o en texto (para la consola).

  También contiene las funciones `linea_*`, que dan formato de una línea a
  cada entidad y que reutilizan los comandos.
  """

  # ========== Datos ==========

  @doc """
  Resumen global: recursos restantes, necesidades pendientes, personas
  localizadas, mensajes y reportes de mascotas, albergues y zonas.
  """
  @spec resumen() :: map()
  def resumen do
    recursos = Inventario.listar()
    necesidades = Necesidades.listar()
    personas = Personas.listar()
    mensajes = Personas.mensajes()
    mascotas = Mascotas.listar()
    albergues = Albergues.listar()

    %{
      zonas: length(Zonas.listar()),
      recursos: existencias(recursos),
      necesidades: %{
        total: length(necesidades),
        pendientes: Enum.count(necesidades, &(&1.estado == :pendiente)),
        por_estado: Enum.frequencies_by(necesidades, & &1.estado)
      },
      personas: %{
        total: length(personas),
        localizadas: Enum.count(personas, &(&1.estado == :localizada)),
        por_estado: Enum.frequencies_by(personas, & &1.estado)
      },
      mensajes: %{total: length(mensajes), pendientes: Enum.count(mensajes, &(&1.estado == :pendiente))},
      mascotas: %{
        total: length(mascotas),
        perdidas: Enum.count(mascotas, &(&1.tipo == :perdida)),
        encontradas: Enum.count(mascotas, &(&1.tipo == :encontrada)),
        por_estado: Enum.frequencies_by(mascotas, & &1.estado)
      },
      albergues: %{
        total: length(albergues),
        ocupacion: albergues |> Enum.map(& &1.ocupacion) |> Enum.sum(),
        capacidad: albergues |> Enum.map(& &1.capacidad) |> Enum.sum()
      }
    }
  end

  # Existencias sumadas por {categoría, unidad}
  defp existencias(recursos) do
    recursos
    |> Enum.group_by(&{&1.categoria, &1.unidad}, & &1.cantidad)
    |> Map.new(fn {clave, cantidades} -> {clave, Enum.sum(cantidades)} end)
  end

  # ========== Texto para la consola ==========

  @doc "Resumen global en texto."
  @spec texto_resumen() :: String.t()
  def texto_resumen do
    r = resumen()

    recursos =
      case Enum.sort(r.recursos) do
        [] -> "  (sin recursos registrados)"
        lista -> Enum.map_join(lista, "\n", fn {{categoria, unidad}, total} -> "  #{categoria}: #{total} #{unidad}" end)
      end

    """
    === Resumen general ===
    Zonas registradas: #{r.zonas}
    Recursos restantes:
    #{recursos}
    Necesidades: #{r.necesidades.total} (pendientes: #{r.necesidades.pendientes})
    Personas: #{r.personas.total} (localizadas: #{r.personas.localizadas})
    Mensajes: #{r.mensajes.total} (pendientes: #{r.mensajes.pendientes})
    Mascotas: #{r.mascotas.total} (perdidas: #{r.mascotas.perdidas}, encontradas: #{r.mascotas.encontradas})
    Albergues: #{r.albergues.total} (ocupación: #{r.albergues.ocupacion}/#{r.albergues.capacidad})
    """
    |> String.trim_trailing()
  end

  @doc "Recursos con existencias iguales o menores al umbral, en texto."
  @spec texto_recursos_criticos(non_neg_integer()) :: String.t()
  def texto_recursos_criticos(umbral \\ 20) do
    umbral
    |> Inventario.criticos()
    |> lista(&linea_recurso/1, "No hay recursos con #{umbral} unidades o menos.")
  end

  @doc "Necesidades pendientes, de la más crítica a la menos crítica, en texto."
  @spec texto_pendientes() :: String.t()
  def texto_pendientes, do: lista(Necesidades.pendientes(), &linea_necesidad/1, "No hay necesidades pendientes.")

  @doc "Une las líneas de una lista o devuelve `vacio` si no hay elementos."
  @spec lista([term()], (term() -> String.t()), String.t()) :: String.t()
  def lista([], _formato, vacio), do: vacio
  def lista(items, formato, _vacio), do: Enum.map_join(items, "\n", formato)

  # ========== Una línea por entidad ==========

  def linea_necesidad(%Necesidad{} = n) do
    "#{n.id} [#{n.prioridad}] #{n.tipo} x#{n.cantidad} (asignado #{Necesidad.total_asignado(n)}) " <>
      "zona=#{n.zona} estado=#{n.estado} resp=#{n.responsable} #{n.descripcion}"
  end

  def linea_recurso(%Recurso{} = r) do
    "#{r.codigo} #{r.nombre}: #{r.cantidad} #{r.unidad} en #{r.ubicacion} (categoría #{r.categoria}) zona=#{r.zona || "sin_asignar"}"
  end

  def linea_persona(%Persona{} = p) do
    "#{p.documento} #{p.nombre} (#{p.edad} años) zona=#{p.zona} estado=#{p.estado}"
  end

  def linea_mensaje(%Mensaje{} = m) do
    "##{m.id} #{m.fecha} de #{m.remitente} para #{m.destinatario} [#{m.estado}]: #{m.contenido}"
  end

  def linea_mascota(%Mascota{} = m) do
    "#{m.id} #{m.tipo} #{m.especie} \"#{m.nombre}\" #{m.color} #{m.tamano} zona=#{m.zona} " <>
      "contacto=#{m.contacto} estado=#{m.estado}"
  end

  def linea_albergue(%{} = a) do
    "#{a.codigo} #{a.nombre} zona=#{a.zona}: #{a.ocupacion}/#{a.capacidad} " <>
      "(#{a.cupos} cupos, #{a.porcentaje}% ocupado)"
  end

  def linea_zona(%Zona{} = z), do: "#{z.codigo} #{z.nombre} nivel=#{z.nivel} afectados=#{Zona.acumulado(z)}"
end
