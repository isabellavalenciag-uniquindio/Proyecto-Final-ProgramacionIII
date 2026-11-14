defmodule EmergenciasWeb.Presentacion do
  @moduledoc "Consultas y formato de los datos reales que presenta la interfaz."

  def secciones do
    [
      %{
        id: "inicio",
        nombre: "Panorama",
        icono: "grid",
        descripcion: "Cada acción cuenta. Aquí empieza la respuesta."
      },
      %{
        id: "zonas",
        nombre: "Zonas de atención",
        icono: "map",
        descripcion: "El territorio, conectado con la ayuda."
      },
      %{
        id: "necesidades",
        nombre: "Necesidades",
        icono: "heart",
        descripcion: "Lo que hace falta. Lo que podemos resolver."
      },
      %{
        id: "recursos",
        nombre: "Recursos",
        icono: "box",
        descripcion: "Suministros disponibles para llegar más lejos."
      },
      %{
        id: "personas",
        nombre: "Personas",
        icono: "users",
        descripcion: "Detrás de cada registro hay alguien que importa."
      },
      %{
        id: "mensajes",
        nombre: "Mensajes",
        icono: "message",
        descripcion: "Acortar distancias. Volver a saber de los nuestros."
      },
      %{
        id: "mascotas",
        nombre: "Mascotas",
        icono: "paw",
        descripcion: "Ellos también son parte de la familia."
      },
      %{
        id: "albergues",
        nombre: "Albergues",
        icono: "home",
        descripcion: "Espacios seguros para un nuevo comienzo."
      },
      %{
        id: "actividad",
        nombre: "Actividad",
        icono: "pulse",
        descripcion: "Las acciones que mantienen conectada a la red."
      }
    ]
  end

  def seccion(id), do: Enum.find(secciones(), &(&1.id == id))

  def cargar(usuario) do
    %{
      zonas: Zonas.listar(),
      necesidades: Necesidades.listar(),
      recursos: Inventario.listar(),
      personas: Personas.listar(),
      mensajes: Personas.mensajes(),
      mascotas: Mascotas.listar(),
      albergues:
        Enum.map(Albergues.listar(), fn resumen ->
          ocupantes =
            case AlbergueProceso.consultar(resumen.codigo) do
              {:ok, a} -> Enum.sort(a.ocupantes)
              _ -> []
            end

          Map.put(resumen, :ocupantes, ocupantes)
        end),
      resumen: Reportes.resumen(),
      actividad:
        Usuarios.actividad(if(usuario.tipo == :administrador, do: nil, else: usuario.usuario), 40),
      usuarios: if(usuario.tipo == :administrador, do: Usuarios.listar(), else: [])
    }
  end

  def filtrar(lista, consulta, zona \\ "") do
    Enum.filter(lista, fn elemento ->
      zona_ok = zona == "" or Map.get(elemento, :zona, Map.get(elemento, :codigo)) == zona
      texto = if(is_struct(elemento), do: Map.from_struct(elemento), else: elemento)
      zona_ok and (consulta == "" or coincide_texto?(texto, consulta))
    end)
  end

  defp coincide_texto?(elemento, consulta) do
    elemento
    |> Map.values()
    |> Enum.filter(&(is_binary(&1) or is_atom(&1) or is_integer(&1)))
    |> Enum.map_join(" ", &to_string/1)
    |> Validacion.normalizar()
    |> String.contains?(Validacion.normalizar(consulta))
  end

  def etiqueta(valor) do
    Map.get(
      %{
        critico: "Crítico",
        critica: "Crítica",
        alto: "Alto",
        alta: "Alta",
        medio: "Medio",
        media: "Media",
        bajo: "Bajo",
        baja: "Baja",
        en_atencion: "En atención",
        primeros_auxilios: "Primeros auxilios",
        sin_informacion: "Sin información",
        en_albergue: "En albergue",
        posible_coincidencia: "Posible coincidencia",
        pequeno: "Pequeño"
      },
      valor,
      valor |> to_string() |> String.replace("_", " ") |> String.capitalize()
    )
  end

  def tono(valor) when valor in [:critico, :critica, :perdida], do: "coral"

  def tono(valor) when valor in [:alto, :alta, :pendiente, :reportada, :posible_coincidencia],
    do: "amber"

  def tono(valor) when valor in [:asignada, :en_atencion, :trasladada, :media, :medio], do: "blue"

  def tono(valor)
      when valor in [
             :atendida,
             :localizada,
             :reunificada,
             :resuelta,
             :entregado,
             :en_albergue,
             :encontrada
           ], do: "green"

  def tono(_), do: "muted"

  def iniciales(nombre),
    do:
      nombre
      |> String.split()
      |> Enum.take(2)
      |> Enum.map_join(&String.first/1)
      |> String.upcase()

  def numero(n),
    do:
      n
      |> to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
      |> String.reverse()

  def corto(texto, limite \\ 45),
    do: if(String.length(texto) > limite, do: String.slice(texto, 0, limite) <> "…", else: texto)

  def accion_actividad(texto) do
    comando = texto |> String.split(" ", parts: 2) |> hd() |> String.trim("\"")

    case EmergenciasWeb.Operaciones.buscar(comando) do
      nil ->
        Map.get(
          %{
            "connect" => "Conexión al sistema",
            "disconnect" => "Cierre de sesión",
            "summary" => "Consulta del panorama",
            "help" => "Consulta de ayuda",
            "list_resources" => "Consulta de recursos",
            "list_needs" => "Consulta de necesidades",
            "find_person" => "Búsqueda de personas",
            "list_family_messages" => "Consulta de mensajes",
            "list_shelters" => "Consulta de albergues",
            "list_pets" => "Consulta de mascotas",
            "list_zones" => "Consulta de zonas",
            "exit" => "Salida de la consola"
          },
          comando,
          "Consulta en la red"
        )

      accion ->
        accion.titulo
    end
  end

  def porcentaje(0, _), do: 0
  def porcentaje(_, 0), do: 0
  def porcentaje(n, total), do: min(100, round(n * 100 / total))
end
