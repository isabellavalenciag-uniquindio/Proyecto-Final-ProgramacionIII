defmodule Comandos do
  @moduledoc """
  Interpreta una línea escrita por el usuario y ejecuta el comando.

  `ejecutar/2` recibe la línea y la sesión (`%{usuario: nil | info}`) y
  devuelve `{estado, texto, sesion}` con estado `:ok`, `:error` o `:salir`.
  No lee ni imprime nada, por eso se puede probar sin consola y usar desde
  varios procesos a la vez, cada uno con su propia sesión.

  Pasos: tokenizar (respetando comillas) → buscar el comando → verificar que
  haya sesión y permiso → validar los argumentos → llamar a la API del dominio.
  """

  @comandos [
    :connect, :disconnect, :help, :exit,
    :register_zone, :register_sector, :register_point, :list_zones, :zone_status,
    :register_need, :list_needs, :pending_needs, :need_status, :cancel_need,
    :register_resource, :resource_in, :resource_out, :list_resources, :critical_resources,
    :assign_resource, :transfer_resource,
    :report_person, :find_person, :update_person,
    :send_family_message, :list_family_messages, :mark_message,
    :report_pet, :list_pets, :match_pets, :confirm_match,
    :register_shelter, :check_shelter, :list_shelters, :shelter_ranking, :shelter_link,
    :register_entry, :register_exit,
    :summary, :list_users, :activity
  ]

  @alias %{"quit" => :exit, "salir" => :exit}

  @usos %{
    connect: "connect usuario contraseña [tipo] [zona] [\"nombre completo\"]",
    disconnect: "disconnect",
    help: "help",
    exit: "exit",
    register_zone: "register_zone codigo nombre nivel [afectados]",
    register_sector: "register_sector zona codigo nombre nivel [afectados]",
    register_point: "register_point zona sector codigo nombre [afectados]",
    list_zones: "list_zones",
    zone_status: "zone_status zona",
    register_need: "register_need tipo cantidad prioridad zona \"descripcion\"",
    list_needs: "list_needs [zona=.. tipo=.. prioridad=.. estado=..]",
    pending_needs: "pending_needs",
    need_status: "need_status id estado",
    cancel_need: "cancel_need id",
    register_resource: "register_resource codigo nombre cantidad unidad ubicacion [categoria] [zona]",
    resource_in: "resource_in codigo ubicacion cantidad",
    resource_out: "resource_out codigo ubicacion cantidad",
    list_resources: "list_resources [categoria=.. ubicacion=.. codigo=.. zona=..]",
    critical_resources: "critical_resources [umbral]",
    assign_resource: "assign_resource id_necesidad recurso cantidad",
    transfer_resource: "transfer_resource codigo origen destino cantidad [zona_destino]",
    report_person: "report_person documento nombre zona estado [edad]",
    find_person: "find_person documento | find_person [nombre=.. zona=.. estado=..]",
    update_person: "update_person documento estado",
    send_family_message: "send_family_message documento \"mensaje\"",
    list_family_messages: "list_family_messages documento",
    mark_message: "mark_message id [pendiente|entregado]",
    report_pet: "report_pet lost|found especie nombre color tamaño zona contacto [caracteristicas]",
    list_pets: "list_pets [especie=.. zona=.. estado=.. tipo=..]",
    match_pets: "match_pets",
    confirm_match: "confirm_match id_perdida id_encontrada",
    register_shelter: "register_shelter codigo \"nombre\" zona capacidad",
    check_shelter: "check_shelter codigo",
    list_shelters: "list_shelters",
    shelter_ranking: "shelter_ranking [cantidad]",
    shelter_link: "shelter_link codigo recurso|necesidad id",
    register_entry: "register_entry codigo documento",
    register_exit: "register_exit codigo documento",
    summary: "summary",
    list_users: "list_users",
    activity: "activity [usuario]"
  }

  @filtros [:zona, :tipo, :prioridad, :estado, :categoria, :ubicacion, :codigo, :nombre, :documento, :especie]

  @doc "Lista de todos los comandos."
  def todos, do: @comandos

  @doc "Texto de uso de un comando."
  def uso(comando), do: Map.fetch!(@usos, comando)

  # ========== Punto de entrada ==========

  @doc """
  Ejecuta una línea de comando.

  ## Ejemplo

      iex> Comandos.ejecutar("help", %{usuario: nil}) |> elem(0)
      :ok
  """
  @spec ejecutar(String.t(), map()) :: {:ok | :error | :salir, String.t(), map()}
  def ejecutar(linea, sesion) do
    sesion = actualizar_sesion(sesion)

    case tokenizar(linea) do
      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}

      [] ->
        {:ok, "", sesion}

      [nombre | args] ->
        with {:ok, comando} <- buscar_comando(nombre),
             :ok <- autorizar(comando, sesion) do
          {estado, texto, nueva} = correr(comando, args, sesion)
          anotar_actividad(comando, linea, sesion, nueva, estado)
          {estado, texto, nueva}
        else
          {:error, razon} -> {:error, mensaje_error(razon), sesion}
        end
    end
  end

  # ========== Tokenizar ==========

  @doc """
  Separa la línea en palabras. Lo que va entre comillas dobles es una sola
  palabra, incluso si está vacía. **Recursiva de cola**, carácter por carácter.

  ## Ejemplos

      iex> Comandos.tokenizar(~s(register_shelter A01 "Albergue Norte" zona_norte 150))
      ["register_shelter", "A01", "Albergue Norte", "zona_norte", "150"]

      iex> Comandos.tokenizar(~s(hola "sin cerrar))
      {:error, :comillas_sin_cerrar}
  """
  @spec tokenizar(String.t()) :: [String.t()] | {:error, :comillas_sin_cerrar}
  def tokenizar(linea) when is_binary(linea), do: linea |> String.trim() |> String.graphemes() |> recorrer([], "", false, false)
  def tokenizar(_), do: []

  defp recorrer([], _tokens, _actual, true, _iniciado), do: {:error, :comillas_sin_cerrar}
  defp recorrer([], tokens, actual, false, iniciado), do: Enum.reverse(cerrar(tokens, actual, iniciado))
  defp recorrer(["\"" | resto], tokens, actual, comillas, _iniciado), do: recorrer(resto, tokens, actual, not comillas, true)

  defp recorrer([g | resto], tokens, actual, false, iniciado) when g in [" ", "\t"] do
    recorrer(resto, cerrar(tokens, actual, iniciado), "", false, false)
  end

  defp recorrer([g | resto], tokens, actual, comillas, _iniciado), do: recorrer(resto, tokens, actual <> g, comillas, true)

  defp cerrar(tokens, _actual, false), do: tokens
  defp cerrar(tokens, actual, true), do: [actual | tokens]

  # ========== Comandos ==========

  defp buscar_comando(nombre) do
    normalizado = Validacion.normalizar(nombre)

    case Map.fetch(@alias, normalizado) do
      {:ok, comando} ->
        {:ok, comando}

      :error ->
        case Enum.find(@comandos, &(Atom.to_string(&1) == normalizado)) do
          nil -> {:error, :comando_desconocido}
          comando -> {:ok, comando}
        end
    end
  end

  defp actualizar_sesion(%{usuario: nil} = sesion), do: sesion

  defp actualizar_sesion(%{usuario: usuario} = sesion) do
    case Usuarios.validar_sesion(usuario) do
      {:ok, actual} -> %{sesion | usuario: actual}
      {:error, :sin_sesion} -> %{sesion | usuario: nil}
    end
  end

  defp autorizar(comando, _sesion) when comando in [:connect, :help, :exit], do: :ok
  defp autorizar(_comando, %{usuario: nil}), do: {:error, :sin_sesion}

  defp autorizar(comando, %{usuario: %{tipo: tipo}}) do
    if Permisos.permitido?(tipo, comando), do: :ok, else: {:error, :sin_permiso}
  end

  # ---- Sesión ----

  defp correr(:connect, [usuario, clave | resto], sesion) when length(resto) <= 3 do
    {tipo, zona, nombre} =
      case resto do
        [t, z, nombre] -> {t, z, nombre}
        [t, z] -> {t, z, nil}
        [t] -> {t, "sin_zona", nil}
        [] -> {"ciudadano", "sin_zona", nil}
      end

    case Usuarios.conectar(usuario, clave, tipo, zona, nombre) do
      {:ok, info} ->
        # Si ya había otra sesión abierta, se cierra
        if sesion.usuario, do: Usuarios.desconectar(sesion.usuario.usuario, sesion.usuario.sesion_id)
        accion = if info.nuevo, do: "registrado y conectado", else: "conectado"
        {:ok, "Usuario #{info.usuario} #{accion} como #{info.tipo} (zona #{info.zona}).", %{sesion | usuario: info}}

      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:disconnect, [], %{usuario: usuario} = sesion) do
    Usuarios.desconectar(usuario.usuario, usuario.sesion_id)
    {:ok, "Usuario #{usuario.usuario} desconectado.", %{sesion | usuario: nil}}
  end

  defp correr(:exit, [], sesion) do
    if sesion.usuario, do: Usuarios.desconectar(sesion.usuario.usuario, sesion.usuario.sesion_id)
    {:salir, "Hasta pronto.", %{sesion | usuario: nil}}
  end

  defp correr(:help, [], sesion), do: {:ok, texto_ayuda(sesion), sesion}

  # ---- Zonas ----

  defp correr(:register_zone, [codigo, nombre, nivel | resto], sesion) when length(resto) <= 1 do
    Zonas.registrar(codigo, nombre, nivel, opcional(resto, 0))
    |> responder(sesion, &"Zona #{&1.codigo} registrada (#{&1.nivel}).")
  end

  defp correr(:register_sector, [zona, codigo, nombre, nivel | resto], sesion) when length(resto) <= 1 do
    Zonas.agregar_sector(zona, codigo, nombre, nivel, opcional(resto, 0))
    |> responder(sesion, fn _ -> "Sector #{codigo} agregado a la zona #{zona}." end)
  end

  defp correr(:register_point, [zona, sector, codigo, nombre | resto], sesion) when length(resto) <= 1 do
    Zonas.agregar_punto(zona, sector, codigo, nombre, opcional(resto, 0))
    |> responder(sesion, fn _ -> "Punto de atención #{codigo} agregado al sector #{sector}." end)
  end

  defp correr(:list_zones, [], sesion) do
    {:ok, Reportes.lista(Zonas.listar(), &Reportes.linea_zona/1, "No hay zonas registradas."), sesion}
  end

  defp correr(:zone_status, [zona], sesion) do
    Zonas.estado(zona) |> responder(sesion, &texto_zona/1)
  end

  # ---- Necesidades ----

  defp correr(:register_need, [tipo, cantidad, prioridad, zona | descripcion], sesion) do
    with :ok <- zona_existe(zona) do
      Necesidades.registrar(tipo, cantidad, prioridad, zona, Enum.join(descripcion, " "), sesion.usuario.usuario)
    end
    |> responder(sesion, &"Necesidad #{&1.id} registrada (#{&1.prioridad}).")
  end

  defp correr(:list_needs, args, sesion) do
    case filtros(args) do
      {:ok, filtros} ->
        {:ok, Reportes.lista(Necesidades.listar(filtros), &Reportes.linea_necesidad/1, "No hay necesidades."), sesion}

      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:pending_needs, [], sesion), do: {:ok, Reportes.texto_pendientes(), sesion}

  defp correr(:need_status, [id, estado], sesion) do
    Necesidades.cambiar_estado(id_necesidad(id), estado)
    |> responder(sesion, &"Necesidad #{&1.id} ahora está #{&1.estado}.")
  end

  defp correr(:cancel_need, [id], sesion) do
    Necesidades.cancelar(id_necesidad(id)) |> responder(sesion, &"Necesidad #{&1.id} cancelada.")
  end

  # ---- Recursos ----

  defp correr(:register_resource, [codigo, nombre, cantidad, unidad, ubicacion | resto], sesion)
       when length(resto) <= 2 do
    zona = Enum.at(resto, 1, sesion.usuario.zona)
    Inventario.registrar(codigo, nombre, opcional(resto, nombre), cantidad, unidad, ubicacion, zona)
    |> responder(sesion, &"Recurso #{&1.codigo} registrado: #{&1.cantidad} #{&1.unidad} en #{&1.ubicacion}.")
  end

  defp correr(:resource_in, [codigo, ubicacion, cantidad], sesion) do
    Inventario.entrada(codigo, ubicacion, cantidad)
    |> responder(sesion, &"Entrada registrada. #{&1.codigo} en #{&1.ubicacion}: #{&1.cantidad} #{&1.unidad}.")
  end

  defp correr(:resource_out, [codigo, ubicacion, cantidad], sesion) do
    Inventario.salida(codigo, ubicacion, cantidad)
    |> responder(sesion, &"Salida registrada. #{&1.codigo} en #{&1.ubicacion}: #{&1.cantidad} #{&1.unidad}.")
  end

  defp correr(:list_resources, args, sesion) do
    case filtros(args, [:categoria, :ubicacion, :codigo, :zona]) do
      {:ok, filtros} ->
        {:ok, Reportes.lista(Inventario.listar(filtros), &Reportes.linea_recurso/1, "No hay recursos."), sesion}

      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:critical_resources, args, sesion) when length(args) <= 1 do
    case Validacion.entero_no_negativo(opcional(args, 20)) do
      {:ok, umbral} -> {:ok, Reportes.texto_recursos_criticos(umbral), sesion}
      {:error, razon} -> {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:assign_resource, [necesidad, recurso, cantidad], sesion) do
    Necesidades.asignar(id_necesidad(necesidad), recurso, cantidad)
    |> responder(sesion, fn n ->
      "Asignación registrada en #{n.id}: #{Necesidad.total_asignado(n)}/#{n.cantidad} (estado #{n.estado})."
    end)
  end

  defp correr(:transfer_resource, [codigo, origen, destino, cantidad | resto], sesion) when length(resto) <= 1 do
    Inventario.transferir(codigo, origen, destino, cantidad, List.first(resto))
    |> responder(sesion, fn %{origen: o, destino: d} ->
      "Transferencia hecha. #{o.ubicacion}: #{o.cantidad} #{o.unidad}; #{d.ubicacion}: #{d.cantidad} #{d.unidad}."
    end)
  end

  # ---- Personas y mensajes ----

  defp correr(:report_person, [documento, nombre, zona, estado | resto], sesion) when length(resto) <= 1 do
    Personas.reportar(documento, nombre, zona, estado, opcional(resto, 0))
    |> responder(sesion, &"Persona #{&1.nombre} (#{&1.documento}) registrada como #{&1.estado}.")
  end

  defp correr(:find_person, [], sesion) do
    {:ok, Reportes.lista(Personas.listar(), &Reportes.linea_persona/1, "No hay personas registradas."), sesion}
  end

  defp correr(:find_person, [documento], sesion) when is_binary(documento) do
    if String.contains?(documento, "=") do
      buscar_personas([documento], sesion)
    else
      buscar_personas(["documento=#{documento}"], sesion)
    end
  end

  defp correr(:find_person, args, sesion), do: buscar_personas(args, sesion)

  defp correr(:update_person, [documento, estado], sesion) do
    Personas.actualizar_estado(documento, estado)
    |> responder(sesion, &"Persona #{&1.documento} ahora está #{&1.estado}.")
  end

  defp correr(:send_family_message, [documento | texto], sesion) when texto != [] do
    Personas.enviar_mensaje(sesion.usuario.usuario, documento, Enum.join(texto, " "))
    |> responder(sesion, &"Mensaje ##{&1.id} guardado para #{&1.destinatario}.")
  end

  defp correr(:list_family_messages, [documento], sesion) do
    {:ok, Reportes.lista(Personas.mensajes(documento), &Reportes.linea_mensaje/1, "No hay mensajes para #{documento}."), sesion}
  end

  defp correr(:mark_message, [id | resto], sesion) when length(resto) <= 1 do
    case Integer.parse(id) do
      {n, ""} when n > 0 ->
        Personas.marcar_mensaje(n, opcional(resto, :entregado))
        |> responder(sesion, &"Mensaje ##{&1.id} marcado como #{&1.estado}.")
      _ -> {:error, mensaje_error(:cantidad_invalida), sesion}
    end
  end

  # ---- Mascotas ----

  defp correr(:report_pet, [tipo, especie, nombre, color, tamano, zona, contacto | caracteristicas], sesion) do
    Mascotas.reportar(tipo, especie, nombre, color, tamano, zona, contacto, Enum.join(caracteristicas, " "))
    |> responder(sesion, &"Reporte #{&1.id} registrado (#{&1.tipo}).")
  end

  defp correr(:list_pets, args, sesion) do
    case filtros(args) do
      {:ok, filtros} ->
        {:ok, Reportes.lista(Mascotas.listar(filtros), &Reportes.linea_mascota/1, "No hay reportes de mascotas."), sesion}

      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:match_pets, [], sesion) do
    texto =
      Reportes.lista(
        Mascotas.coincidencias(),
        fn p -> "#{p.perdida} (perdida) ~ #{p.encontrada} (encontrada): #{p.puntaje} puntos" end,
        "No se encontraron coincidencias."
      )

    {:ok, texto, sesion}
  end

  defp correr(:confirm_match, [a, b], sesion) do
    Mascotas.confirmar(id_mascota(a), id_mascota(b))
    |> responder(sesion, &"Coincidencia confirmada: #{&1.perdida.id} y #{&1.encontrada.id} quedaron resueltas.")
  end

  # ---- Albergues ----

  defp correr(:register_shelter, [codigo, nombre, zona, capacidad], sesion) do
    with :ok <- zona_existe(zona) do
      Albergues.registrar(codigo, nombre, zona, capacidad)
    end
    |> responder(sesion, &"Albergue #{&1.codigo} registrado con capacidad #{&1.capacidad}.")
  end

  defp correr(:check_shelter, [codigo], sesion) do
    Albergues.consultar(codigo) |> responder(sesion, &Reportes.linea_albergue/1)
  end

  defp correr(:list_shelters, [], sesion) do
    {:ok, Reportes.lista(Albergues.listar(), &Reportes.linea_albergue/1, "No hay albergues."), sesion}
  end

  defp correr(:shelter_ranking, args, sesion) when length(args) <= 1 do
    case Validacion.entero_positivo(opcional(args, 5)) do
      {:ok, n} -> {:ok, Reportes.lista(Albergues.ranking(n), &Reportes.linea_albergue/1, "No hay albergues."), sesion}
      {:error, razon} -> {:error, mensaje_error(razon), sesion}
    end
  end

  defp correr(:shelter_link, [codigo, tipo, id], sesion) do
    resultado =
      case Validacion.atomo(tipo, [:recurso, :necesidad], :tipo_invalido) do
        {:ok, :recurso} -> Albergues.asociar_recurso(codigo, id)
        {:ok, :necesidad} -> Albergues.asociar_necesidad(codigo, id_necesidad(id))
        {:error, _} = error -> error
      end

    responder(resultado, sesion, fn _ -> "#{tipo} #{id} asociado al albergue #{codigo}." end)
  end

  defp correr(:register_entry, [codigo, documento], sesion) do
    Albergues.ingresar(codigo, documento)
    |> responder(sesion, &"Ingreso registrado. Ocupación #{&1.ocupacion}/#{&1.capacidad} (#{&1.cupos} cupos).")
  end

  defp correr(:register_exit, [codigo, documento], sesion) do
    Albergues.salir(codigo, documento)
    |> responder(sesion, &"Salida registrada. Ocupación #{&1.ocupacion}/#{&1.capacidad} (#{&1.cupos} cupos).")
  end

  # ---- Reportes y administración ----

  defp correr(:summary, [], sesion), do: {:ok, Reportes.texto_resumen(), sesion}

  defp correr(:list_users, [], sesion) do
    texto =
      Reportes.lista(
        Usuarios.listar(),
        fn u -> "#{u.usuario} (#{u.tipo}) zona=#{u.zona} #{if u.conectado, do: "[conectado]", else: ""}" end,
        "No hay usuarios."
      )

    {:ok, texto, sesion}
  end

  defp correr(:activity, args, sesion) when length(args) <= 1 do
    texto =
      Reportes.lista(
        Usuarios.actividad(List.first(args), 20),
        fn {usuario, fecha, comando} -> "#{fecha} #{usuario}: #{comando}" end,
        "Sin actividad registrada."
      )

    {:ok, texto, sesion}
  end

  # Argumentos que no corresponden a ningún formato válido del comando
  defp correr(comando, _args, sesion), do: {:error, "Uso: " <> uso(comando), sesion}

  # ========== Funciones auxiliares ==========

  defp responder({:ok, valor}, sesion, formato), do: {:ok, formato.(valor), sesion}
  defp responder({:error, razon}, sesion, _formato), do: {:error, mensaje_error(razon), sesion}

  defp opcional([], valor_por_defecto), do: valor_por_defecto
  defp opcional([valor | _], _valor_por_defecto), do: valor

  defp zona_existe(zona) do
    if Zonas.existe?(zona), do: :ok, else: {:error, {:zona_inexistente, zona}}
  end

  # "need001", "n1" o "N001" -> "N001"
  defp id_necesidad(texto), do: id_con_prefijo(texto, "N")
  defp id_mascota(texto), do: id_con_prefijo(texto, "M")

  defp id_con_prefijo(texto, prefijo) do
    case Regex.run(~r/\d+/, texto) do
      [digitos] -> prefijo <> String.pad_leading(Integer.to_string(String.to_integer(digitos)), 3, "0")
      nil -> texto
    end
  end

  # "zona=centro prioridad=critica" -> [zona: "centro", prioridad: "critica"]
  defp filtros(args, permitidos \\ @filtros) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acumulado} ->
      with [clave, valor] <- String.split(arg, "=", parts: 2),
           campo when not is_nil(campo) <- Enum.find(permitidos, &(Atom.to_string(&1) == Validacion.normalizar(clave))) do
        {:cont, {:ok, acumulado ++ [{campo, valor}]}}
      else
        _ -> {:halt, {:error, {:filtro_invalido, arg}}}
      end
    end)
  end

  defp buscar_personas(args, sesion) do
    case filtros(args) do
      {:ok, filtros} ->
        {:ok, Reportes.lista(Personas.buscar(filtros), &Reportes.linea_persona/1, "No se encontraron personas."), sesion}

      {:error, razon} ->
        {:error, mensaje_error(razon), sesion}
    end
  end

  defp texto_zona(%{} = z) do
    sectores =
      Reportes.lista(
        z.sectores,
        fn s ->
          "  - #{s.codigo} #{s.nombre} (#{s.nivel}): #{s.estadisticas.afectados} afectados, " <>
            "#{s.estadisticas.puntos} puntos de atención"
        end,
        "  (sin sectores)"
      )

    "Zona #{z.codigo} #{z.nombre} (#{z.nivel}): #{z.estadisticas.afectados} afectados, " <>
      "#{z.estadisticas.sectores} sectores, #{z.estadisticas.puntos} puntos\n#{sectores}"
  end

  defp texto_ayuda(%{usuario: nil}) do
    "Comandos disponibles sin conectarse:\n  #{uso(:connect)}\n  #{uso(:help)}\n  #{uso(:exit)}"
  end

  defp texto_ayuda(%{usuario: %{tipo: tipo}}) do
    lista = Enum.filter(@comandos, &(&1 in [:help, :exit] or Permisos.permitido?(tipo, &1)))
    "Comandos para #{tipo}:\n" <> Enum.map_join(lista, "\n", &("  " <> uso(&1)))
  end

  # Guarda en la actividad del usuario lo que hizo (nunca su contraseña)
  defp anotar_actividad(:connect, _linea, _antes, %{usuario: %{usuario: u}}, :ok) do
    Usuarios.registrar_actividad(u, "connect #{u}")
  end

  defp anotar_actividad(:connect, _linea, _antes, _despues, _estado), do: :ok

  defp anotar_actividad(_comando, linea, antes, despues, _estado) do
    case antes.usuario || despues.usuario do
      nil -> :ok
      %{usuario: u} -> Usuarios.registrar_actividad(u, linea)
    end
  end

  # ========== Mensajes de error ==========

  @doc "Texto en español para un motivo de error."
  @spec mensaje_error(term()) :: String.t()
  def mensaje_error(:comando_desconocido), do: "Comando desconocido. Escriba help para ver los comandos."
  def mensaje_error(:sin_sesion), do: "Debe conectarse primero: #{uso(:connect)}"
  def mensaje_error(:sin_permiso), do: "Su tipo de usuario no puede ejecutar ese comando."
  def mensaje_error(:comillas_sin_cerrar), do: "Hay unas comillas sin cerrar."
  def mensaje_error({:filtro_invalido, arg}), do: "Filtro inválido: #{arg}. Use campo=valor."
  def mensaje_error({:zona_inexistente, z}), do: "La zona #{z} no existe. Regístrela con register_zone."
  def mensaje_error({:recurso_inexistente, id}), do: "El recurso #{id} no existe."
  def mensaje_error({:necesidad_inexistente, id}), do: "La necesidad #{id} no existe."
  def mensaje_error(:clave_incorrecta), do: "Contraseña incorrecta."
  def mensaje_error(:clave_corta), do: "La contraseña debe tener al menos 4 caracteres."
  def mensaje_error(:usuario_invalido), do: "Nombre de usuario inválido."
  def mensaje_error(:duplicado), do: "Ya existe un registro con ese identificador."
  def mensaje_error(:codigo_duplicado), do: "Ese código ya existe en la zona."
  def mensaje_error(:no_existe), do: "No se encontró lo que busca."
  def mensaje_error(:no_disponible), do: "El albergue se está recuperando. Intente nuevamente."
  def mensaje_error(:padre_no_existe), do: "El elemento superior (zona o sector) no existe."
  def mensaje_error(:jerarquia_invalida), do: "Esa jerarquía no es válida (zona → sector → punto)."
  def mensaje_error(:insuficiente), do: "No hay existencias suficientes."
  def mensaje_error(:excede_requerida), do: "La cantidad supera lo que le falta a la necesidad."
  def mensaje_error(:recursos_incompletos), do: "Primero debe cubrir toda la cantidad requerida con recursos compatibles."
  def mensaje_error(:recurso_incompatible), do: "El recurso no corresponde al tipo de necesidad."
  def mensaje_error(:cantidad_invalida), do: "La cantidad o el número no es válido (debe ser un entero positivo)."
  def mensaje_error(:mismo_lugar), do: "El origen y el destino son el mismo lugar."
  def mensaje_error(:zona_destino_distinta), do: "La zona indicada no corresponde al recurso del destino."
  def mensaje_error(:texto_vacio), do: "Falta un dato obligatorio."
  def mensaje_error(:tipo_invalido), do: "El tipo indicado no es válido."
  def mensaje_error(:prioridad_invalida), do: "Prioridad inválida (critica, alta, media o baja)."
  def mensaje_error(:nivel_invalido), do: "Nivel inválido (critico, alto, medio o bajo)."
  def mensaje_error(:estado_invalido), do: "El estado no es válido o no se permite para esa operación."
  def mensaje_error(:transicion_invalida), do: "Ese cambio de estado no está permitido."
  def mensaje_error(:mismo_estado), do: "Ya tiene ese estado."
  def mensaje_error(:ya_cerrada), do: "Ya está cerrada y no admite más cambios."
  def mensaje_error(:ya_resuelta), do: "Ese reporte ya está resuelto."
  def mensaje_error(:ya_entregado), do: "El mensaje ya estaba entregado."
  def mensaje_error(:par_invalido), do: "Debe indicar una mascota perdida y una encontrada."
  def mensaje_error(:especie_distinta), do: "Las mascotas son de especies distintas."
  def mensaje_error(:tamano_invalido), do: "Tamaño inválido (pequeño, mediano o grande)."
  def mensaje_error(:edad_invalida), do: "La edad no es válida."
  def mensaje_error(:mensaje_largo), do: "El mensaje es demasiado largo (máximo 500 caracteres)."
  def mensaje_error(:sin_cupo), do: "El albergue no tiene cupos disponibles."
  def mensaje_error(:ya_registrado), do: "Esa persona ya está en el albergue."
  def mensaje_error(:en_otro_albergue), do: "Esa persona ya ocupa otro albergue; primero debe registrar su salida."
  def mensaje_error(:no_esta), do: "Esa persona no está en el albergue."
  def mensaje_error(:no_conectado), do: "El usuario no estaba conectado."
  def mensaje_error(otro), do: "Error: #{inspect(otro)}"
end
