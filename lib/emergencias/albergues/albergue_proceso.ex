defmodule AlbergueProceso do
  @moduledoc """
  Proceso de un albergue: **un GenServer por albergue**.

  Como cada albergue es su propio proceso, los ingresos a un mismo albergue se
  atienden uno a uno y la ocupación nunca supera la capacidad, mientras que
  los ingresos a albergues distintos avanzan en paralelo.

  Se registra en un `Registry` con el código del albergue como nombre. Cada
  cambio se guarda en su fila del CSV; si el proceso falla y su supervisor lo
  reinicia, `init/1` recupera el estado desde allí.
  """
  use GenServer

  @registro Emergencias.RegistroAlbergues

  # ========== API del cliente ==========

  def start_link(%Albergue{} = albergue) do
    GenServer.start_link(__MODULE__, albergue, name: via(albergue.codigo))
  end

  @doc "Nombre del proceso dentro del `Registry`."
  def via(codigo), do: {:via, Registry, {@registro, codigo}}

  @doc "Códigos de todos los albergues activos."
  @spec codigos() :: [String.t()]
  def codigos, do: @registro |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}]) |> Enum.sort()

  @spec consultar(String.t()) :: {:ok, %Albergue{}} | {:error, :no_existe}
  def consultar(codigo), do: llamar(codigo, :consultar)

  @spec ingresar(String.t(), term()) :: {:ok, map()} | {:error, atom()}
  def ingresar(codigo, documento) do
    con_documento(documento, fn documento ->
      with {:ok, _} <- consultar(codigo),
           :ok <- verificar_otro_albergue(codigo, documento),
           {:ok, resumen} <- llamar(codigo, {:ingresar, documento}) do
        case Personas.actualizar_estado(documento, :en_albergue) do
          {:ok, _} -> {:ok, resumen}
          {:error, razon} when razon in [:no_existe, :mismo_estado] -> {:ok, resumen}
          {:error, _} = error ->
            llamar(codigo, {:salir, documento})
            error
        end
      end
    end)
  end

  @spec salir(String.t(), term()) :: {:ok, map()} | {:error, atom()}
  def salir(codigo, documento) do
    con_documento(documento, fn documento ->
      with {:ok, resumen} <- llamar(codigo, {:salir, documento}) do
        case Personas.obtener(documento) do
          {:ok, %Persona{estado: :en_albergue}} -> Personas.actualizar_estado(documento, :trasladada)
          _ -> :ok
        end
        {:ok, resumen}
      end
    end)
  end

  # El bloqueo pertenece al solicitante y solo serializa operaciones sobre
  # la misma persona. Personas distintas pueden operar en paralelo.
  defp con_documento(documento, funcion) do
    with {:ok, documento} <- Validacion.texto(documento) do
      :global.trans({{__MODULE__, documento}, self()}, fn -> funcion.(documento) end, [node()])
    end
  end

  defp verificar_otro_albergue(codigo, documento) do
    # Las copias guardadas cubren el intervalo en que otro albergue se reinicia.
    guardado = Persistencia.cargar(:albergues)
      |> Enum.map(&Albergue.desde_fila/1)
      |> Enum.any?(fn a -> a.codigo != codigo and MapSet.member?(a.ocupantes, documento) end)

    ocupado = guardado or Enum.any?(codigos(), fn otro ->
      otro != codigo and
        case consultar(otro) do
          {:ok, albergue} -> MapSet.member?(albergue.ocupantes, documento)
          _ -> false
        end
    end)

    if ocupado, do: {:error, :en_otro_albergue}, else: :ok
  end

  @spec asociar(String.t(), :recurso | :necesidad, String.t()) :: {:ok, map()} | {:error, atom()}
  def asociar(codigo, tipo, id), do: llamar(codigo, {:asociar, tipo, id})

  defp llamar(codigo, mensaje) do
    case Registry.lookup(@registro, codigo) do
      [] -> {:error, :no_existe}
      [_ | _] -> GenServer.call(via(codigo), mensaje)
    end
  rescue
    ArgumentError -> {:error, :no_disponible}
  catch
    :exit, _ -> {:error, :no_disponible}
  end

  # ========== Callbacks del servidor ==========

  @impl true
  def init(%Albergue{} = inicial) do
    albergue = recuperar(inicial)
    Persistencia.guardar_fila(:albergues, Albergue.a_fila(albergue))
    {:ok, albergue}
  end

  @impl true
  def handle_call(:consultar, _from, albergue), do: {:reply, {:ok, albergue}, albergue}

  def handle_call({:ingresar, documento}, _from, albergue) do
    responder(Albergue.ingresar(albergue, documento), albergue)
  end

  def handle_call({:salir, documento}, _from, albergue) do
    responder(Albergue.salir(albergue, documento), albergue)
  end

  def handle_call({:asociar, tipo, id}, _from, albergue) do
    resultado = with {:ok, id} <- Validacion.texto(id),
                     :ok <- validar_referencia(tipo, id) do
      Albergue.asociar(albergue, tipo, id)
    end
    responder(resultado, albergue)
  end

  defp validar_referencia(:recurso, id) do
    if Enum.any?(Inventario.listar(codigo: id), &(&1.codigo == id)),
      do: :ok, else: {:error, {:recurso_inexistente, id}}
  end

  defp validar_referencia(:necesidad, id) do
    case Necesidades.obtener(id) do
      {:ok, _} -> :ok
      {:error, :no_existe} -> {:error, {:necesidad_inexistente, id}}
    end
  end

  defp validar_referencia(_, _), do: {:error, :tipo_invalido}

  # ========== Funciones auxiliares ==========

  defp responder({:ok, nuevo}, _anterior) do
    Persistencia.guardar_fila(:albergues, Albergue.a_fila(nuevo))
    {:reply, {:ok, Albergue.resumen(nuevo)}, nuevo}
  end

  defp responder({:error, _} = error, anterior), do: {:reply, error, anterior}

  # Si ya hay una copia guardada (reinicio tras un fallo), se usa esa
  defp recuperar(%Albergue{codigo: codigo} = inicial) do
    case Enum.find(Persistencia.cargar(:albergues), fn [c | _] -> c == codigo end) do
      nil -> inicial
      fila -> Albergue.desde_fila(fila)
    end
  end
end
