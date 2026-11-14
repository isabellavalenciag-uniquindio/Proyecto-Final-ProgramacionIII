defmodule Usuarios do
  @moduledoc """
  Proceso que guarda los usuarios, quiénes están conectados y el registro de
  actividad.

  `conectar/5` es un `call`, así que se atiende uno a uno: si dos personas
  intentan crear el mismo usuario a la vez, la primera lo registra y la
  segunda ya lo encuentra y le valida la contraseña.

  Las sesiones (quién está conectado) viven solo en memoria; los usuarios y la
  actividad se guardan en `usuarios.csv` y `actividad.csv`.
  """
  use GenServer

  @max_actividad 500

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Conecta al usuario. Si no existe lo registra automáticamente con los datos
  dados; si existe valida la contraseña (y conserva su nombre, tipo y zona).
  El nombre completo es opcional para mantener las conexiones anteriores.
  """
  @spec conectar(term(), term(), term(), term(), term()) :: {:ok, map()} | {:error, atom()}
  def conectar(usuario, clave, tipo, zona, nombre_completo \\ nil),
    do: GenServer.call(__MODULE__, {:conectar, usuario, clave, tipo, zona, nombre_completo})

  @doc "Autentica una cuenta existente sin registrar usuarios desconocidos."
  @spec autenticar(term(), term()) :: {:ok, map()} | {:error, :credenciales_invalidas}
  def autenticar(usuario, clave), do: GenServer.call(__MODULE__, {:autenticar, usuario, clave})

  @doc "Registra y conecta una cuenta nueva de forma atómica; rechaza usuarios existentes."
  @spec registrar_y_conectar(term(), term(), term(), term(), term()) ::
          {:ok, map()} | {:error, atom()}
  def registrar_y_conectar(usuario, clave, nombre, tipo, zona) do
    GenServer.call(__MODULE__, {:registrar_y_conectar, usuario, clave, nombre, tipo, zona})
  end

  @doc "Registra un usuario sin conectarlo."
  @spec registrar(term(), term(), term(), term(), term()) :: {:ok, map()} | {:error, atom()}
  def registrar(usuario, clave, nombre, tipo, zona) do
    GenServer.call(__MODULE__, {:registrar, usuario, clave, nombre, tipo, zona})
  end

  @doc "Desconecta una sesión, o todas las del usuario si no se indica una."
  @spec desconectar(String.t(), reference() | :todas) :: :ok | {:error, :no_conectado}
  def desconectar(usuario, sesion_id \\ :todas) do
    resultado = GenServer.call(__MODULE__, {:desconectar, usuario, sesion_id})
    if resultado == :ok, do: Emergencias.Eventos.notificar(:sesiones)
    resultado
  end

  @doc "Valida una sesión en memoria y devuelve los datos actuales del usuario."
  @spec validar_sesion(map()) :: {:ok, map()} | {:error, :sin_sesion}
  def validar_sesion(%{usuario: usuario, sesion_id: sesion_id}) do
    GenServer.call(__MODULE__, {:validar_sesion, usuario, sesion_id})
  end

  def validar_sesion(_), do: {:error, :sin_sesion}

  @spec conectado?(String.t()) :: boolean()
  def conectado?(usuario), do: GenServer.call(__MODULE__, {:conectado?, usuario})

  @doc "Anota un comando en la actividad del usuario (no espera respuesta)."
  @spec registrar_actividad(String.t(), String.t()) :: :ok
  def registrar_actividad(usuario, comando), do: GenServer.cast(__MODULE__, {:actividad, usuario, comando})

  @doc "Últimas acciones de un usuario (o de todos si es `nil`), la más reciente primero."
  @spec actividad(String.t() | nil, pos_integer()) :: [{String.t(), String.t(), String.t()}]
  def actividad(usuario \\ nil, limite \\ 20), do: GenServer.call(__MODULE__, {:actividad, usuario, limite})

  @doc "Lista los usuarios (sin contraseña) indicando si están conectados."
  @spec listar() :: [map()]
  def listar, do: GenServer.call(__MODULE__, :listar)

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    usuarios =
      :usuarios
      |> Persistencia.cargar()
      |> Enum.map(&Usuario.desde_fila/1)
      |> Map.new(fn u -> {u.usuario, u} end)

    actividad = :actividad |> Persistencia.cargar() |> Enum.map(fn [u, fecha, comando] -> {u, fecha, comando} end)

    {:ok, %{usuarios: usuarios, conectados: %{}, actividad: actividad}}
  end

  @impl true
  def handle_call({:autenticar, usuario, clave}, _from, estado) do
    with {:ok, existente} <- Map.fetch(estado.usuarios, Usuario.normalizar_usuario(usuario)),
         true <- Usuario.verificar_clave(existente, clave) do
      {sesion, actualizado} = conectar_sesion(estado, existente, false)
      {:reply, {:ok, sesion}, actualizado}
    else
      _ -> {:reply, {:error, :credenciales_invalidas}, estado}
    end
  end

  def handle_call({:registrar_y_conectar, usuario, clave, nombre, tipo, zona}, _from, estado) do
    with {:ok, nuevo} <- Usuario.nuevo(usuario, clave, nombre, tipo, zona),
         false <- Map.has_key?(estado.usuarios, nuevo.usuario) do
      {sesion, actualizado} = estado |> agregar(nuevo) |> conectar_sesion(nuevo, true)
      {:reply, {:ok, sesion}, actualizado}
    else
      true -> {:reply, {:error, :duplicado}, estado}
      {:error, _} = error -> {:reply, error, estado}
    end
  end

  def handle_call({:conectar, usuario, clave, tipo, zona, nombre_completo}, _from, estado) do
    nombre = Usuario.normalizar_usuario(usuario)

    case Map.fetch(estado.usuarios, nombre) do
      {:ok, existente} ->
        if Usuario.verificar_clave(existente, clave) do
          {sesion, actualizado} = conectar_sesion(estado, existente, false)
          {:reply, {:ok, sesion}, actualizado}
        else
          {:reply, {:error, :clave_incorrecta}, estado}
        end

      :error ->
        case Usuario.nuevo(usuario, clave, nombre_completo || usuario, tipo, zona) do
          {:ok, nuevo} ->
            {sesion, actualizado} = estado |> agregar(nuevo) |> conectar_sesion(nuevo, true)
            {:reply, {:ok, sesion}, actualizado}

          {:error, _} = error ->
            {:reply, error, estado}
        end
    end
  end

  def handle_call({:registrar, usuario, clave, nombre, tipo, zona}, _from, estado) do
    with {:ok, nuevo} <- Usuario.nuevo(usuario, clave, nombre, tipo, zona),
         false <- Map.has_key?(estado.usuarios, nuevo.usuario) do
      {:reply, {:ok, info(nuevo, true)}, agregar(estado, nuevo)}
    else
      true -> {:reply, {:error, :duplicado}, estado}
      {:error, _} = error -> {:reply, error, estado}
    end
  end

  def handle_call({:desconectar, usuario, sesion_id}, _from, estado) do
    nombre = Usuario.normalizar_usuario(usuario)

    case Map.fetch(estado.conectados, nombre) do
      {:ok, sesiones} ->
        cond do
          sesion_id == :todas ->
            {:reply, :ok, %{estado | conectados: Map.delete(estado.conectados, nombre)}}

          MapSet.member?(sesiones, sesion_id) ->
            restantes = MapSet.delete(sesiones, sesion_id)
            conectados =
              if MapSet.size(restantes) == 0,
                do: Map.delete(estado.conectados, nombre),
                else: Map.put(estado.conectados, nombre, restantes)

            {:reply, :ok, %{estado | conectados: conectados}}

          true ->
            {:reply, {:error, :no_conectado}, estado}
        end

      :error ->
        {:reply, {:error, :no_conectado}, estado}
    end
  end

  def handle_call({:conectado?, usuario}, _from, estado) do
    {:reply, Map.has_key?(estado.conectados, Usuario.normalizar_usuario(usuario)), estado}
  end

  def handle_call({:validar_sesion, usuario, sesion_id}, _from, estado) do
    resultado =
      with {:ok, sesiones} <- Map.fetch(estado.conectados, usuario),
           true <- MapSet.member?(sesiones, sesion_id),
           {:ok, u} <- Map.fetch(estado.usuarios, usuario) do
        {:ok, Map.put(info(u, false), :sesion_id, sesion_id)}
      else
        _ -> {:error, :sin_sesion}
      end

    {:reply, resultado, estado}
  end

  def handle_call({:actividad, usuario, limite}, _from, estado) do
    filtrada =
      case usuario do
        nil -> estado.actividad
        u -> Enum.filter(estado.actividad, fn {quien, _, _} -> quien == Usuario.normalizar_usuario(u) end)
      end

    {:reply, Enum.take(filtrada, limite), estado}
  end

  def handle_call(:listar, _from, estado) do
    lista =
      estado.usuarios
      |> Map.values()
      |> Enum.sort_by(& &1.usuario)
      |> Enum.map(fn u -> Map.put(info(u, false), :conectado, Map.has_key?(estado.conectados, u.usuario)) end)

    {:reply, lista, estado}
  end

  @impl true
  def handle_cast({:actividad, usuario, comando}, estado) do
    entrada = {usuario, fecha(), Archivo.sanear(comando)}
    actividad = Enum.take([entrada | estado.actividad], @max_actividad)
    Persistencia.guardar(:actividad, Enum.map(actividad, fn {u, f, c} -> [u, f, c] end))
    {:noreply, %{estado | actividad: actividad}}
  end

  # ========== Funciones auxiliares ==========

  defp info(u, nuevo), do: %{usuario: u.usuario, nombre: u.nombre, tipo: u.tipo, zona: u.zona, nuevo: nuevo}

  defp conectar_sesion(estado, usuario, nuevo) do
    sesion_id = make_ref()
    conectados = Map.update(estado.conectados, usuario.usuario, MapSet.new([sesion_id]), &MapSet.put(&1, sesion_id))
    {Map.put(info(usuario, nuevo), :sesion_id, sesion_id), %{estado | conectados: conectados}}
  end

  defp agregar(estado, usuario) do
    usuarios = Map.put(estado.usuarios, usuario.usuario, usuario)

    filas = usuarios |> Map.values() |> Enum.sort_by(& &1.usuario) |> Enum.map(&Usuario.a_fila/1)
    Persistencia.guardar(:usuarios, filas)
    %{estado | usuarios: usuarios}
  end

  defp fecha, do: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
end
