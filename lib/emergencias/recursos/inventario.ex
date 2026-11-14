defmodule Inventario do
  @moduledoc """
  Inventario de recursos. **Es un único proceso**, y de ahí sale la garantía
  de concurrencia: los mensajes se atienden uno a uno, así que dos solicitudes
  simultáneas nunca leen el mismo saldo. Si hay 50 litros y llegan a la vez
  solicitudes de 30 y 25, se atiende primero una y la otra recibe
  `{:error, :insuficiente}`. Nunca se asigna más de lo que existe.

  ## Estado

  Un mapa `%{{codigo, ubicacion} => %Recurso{}}`. Se eligió un mapa porque
  permite acceso directo por clave. Se carga de `Persistencia` en `init/1` y
  se guarda tras cada cambio.

  ## Reservas

  `reservar/2` recibe un código **o una categoría** (`"R001"` o `"agua"`),
  toma las unidades de uno o varios lugares, todo o nada, y devuelve el
  detalle `[{codigo, ubicacion, cantidad}]` para poder devolverlo con
  `liberar/1`.
  """
  use GenServer

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Registra un recurso nuevo. Error `:duplicado` si ya existe ese código en ese lugar."
  @spec registrar(term(), term(), term(), term(), term(), term(), term()) ::
          {:ok, %Recurso{}} | {:error, atom()}
  def registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona \\ nil) do
    GenServer.call(__MODULE__, {:registrar, {codigo, nombre, categoria, cantidad, unidad, ubicacion, zona}})
  end

  @doc "Registra una entrada de inventario."
  @spec entrada(String.t(), String.t(), term()) :: {:ok, %Recurso{}} | {:error, atom()}
  def entrada(codigo, ubicacion, cantidad) do
    GenServer.call(__MODULE__, {:mover, :entrada, codigo, ubicacion, cantidad})
  end

  @doc "Registra una salida de inventario. Error `:insuficiente` si no alcanza."
  @spec salida(String.t(), String.t(), term()) :: {:ok, %Recurso{}} | {:error, atom()}
  def salida(codigo, ubicacion, cantidad) do
    GenServer.call(__MODULE__, {:mover, :salida, codigo, ubicacion, cantidad})
  end

  @doc """
  Reserva unidades por código o categoría. Operación atómica.

  Devuelve `{:ok, detalle}` o `{:error, :insuficiente}`.
  """
  @spec reservar(String.t(), term(), atom() | nil) :: {:ok, [{String.t(), String.t(), pos_integer()}]} | {:error, atom()}
  def reservar(clave, cantidad, tipo \\ nil), do: GenServer.call(__MODULE__, {:reservar, clave, cantidad, tipo})

  @doc "Devuelve al inventario lo que entregó `reservar/2`."
  @spec liberar([{String.t(), String.t(), pos_integer()}]) :: :ok
  def liberar(detalle), do: GenServer.call(__MODULE__, {:liberar, detalle})

  @doc "Transfiere unidades entre dos lugares. Crea el recurso en el destino si no existe."
  @spec transferir(String.t(), String.t(), String.t(), term(), String.t() | nil) :: {:ok, map()} | {:error, atom()}
  def transferir(codigo, origen, destino, cantidad, zona_destino \\ nil) do
    zona_destino = zona_destino || zona_albergue(destino)
    GenServer.call(__MODULE__, {:transferir, codigo, origen, destino, cantidad, zona_destino})
  end

  @doc "Busca un recurso por código y lugar."
  @spec obtener(String.t(), String.t()) :: {:ok, %Recurso{}} | {:error, :no_existe}
  def obtener(codigo, ubicacion), do: GenServer.call(__MODULE__, {:obtener, codigo, ubicacion})

  @doc "Lista recursos. Filtros opcionales: `categoria:`, `ubicacion:`, `codigo:`, `zona:`."
  @spec listar(keyword()) :: [%Recurso{}]
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Total disponible de un código o categoría, opcionalmente por ubicación y zona."
  @spec disponibilidad(String.t(), String.t() | nil, String.t() | nil) :: non_neg_integer()
  def disponibilidad(clave, ubicacion \\ nil, zona \\ nil) do
    GenServer.call(__MODULE__, {:disponibilidad, clave, ubicacion, zona})
  end

  @doc "Recursos con existencias iguales o menores al umbral, de menor a mayor."
  @spec criticos(non_neg_integer()) :: [%Recurso{}]
  def criticos(umbral \\ 20), do: GenServer.call(__MODULE__, {:criticos, umbral})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    recursos =
      :recursos
      |> Persistencia.cargar()
      |> Enum.map(&Recurso.desde_fila/1)
      |> Map.new(fn r -> {Recurso.clave(r), r} end)

    {:ok, recursos}
  end

  @impl true
  def handle_call({:registrar, {codigo, nombre, categoria, cantidad, unidad, ubicacion, zona}}, _from, recursos) do
    case crear_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona) do
      {:ok, recurso} ->
        if Map.has_key?(recursos, Recurso.clave(recurso)) do
          {:reply, {:error, :duplicado}, recursos}
        else
          {:reply, {:ok, recurso}, guardar(Map.put(recursos, Recurso.clave(recurso), recurso))}
        end

      {:error, _} = error ->
        {:reply, error, recursos}
    end
  end

  def handle_call({:mover, tipo, codigo, ubicacion, cantidad}, _from, recursos) do
    with {:ok, recurso} <- buscar(recursos, codigo, ubicacion),
         {:ok, actualizado} <- aplicar(recurso, tipo, cantidad) do
      {:reply, {:ok, actualizado}, guardar(Map.put(recursos, Recurso.clave(actualizado), actualizado))}
    else
      {:error, _} = error -> {:reply, error, recursos}
    end
  end

  def handle_call({:reservar, clave, cantidad, tipo}, _from, recursos) do
    with {:ok, cantidad} <- Validacion.entero_positivo(cantidad),
         candidatos = candidatos(recursos, clave),
         {:ok, candidatos} <- compatibles(candidatos, tipo),
         {:ok, detalle} <- tomar(candidatos, cantidad, []) do
      nuevos =
        Enum.reduce(detalle, recursos, fn {codigo, ubicacion, n}, acc ->
          {:ok, actualizado} = Recurso.restar(Map.fetch!(acc, {codigo, ubicacion}), n, :reserva)
          Map.put(acc, {codigo, ubicacion}, actualizado)
        end)

      {:reply, {:ok, detalle}, guardar(nuevos)}
    else
      {:error, _} = error -> {:reply, error, recursos}
    end
  end

  def handle_call({:liberar, detalle}, _from, recursos) do
    nuevos =
      Enum.reduce(detalle, recursos, fn {codigo, ubicacion, n}, acc ->
        case Map.fetch(acc, {codigo, ubicacion}) do
          {:ok, recurso} ->
            {:ok, actualizado} = Recurso.sumar(recurso, n, :liberacion)
            Map.put(acc, {codigo, ubicacion}, actualizado)

          :error ->
            acc
        end
      end)

    {:reply, :ok, guardar(nuevos)}
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad, zona_destino}, _from, recursos) do
    with {:ok, codigo} <- Validacion.texto(codigo),
         {:ok, origen} <- Validacion.texto(origen),
         {:ok, destino} <- Validacion.texto(destino),
         :ok <- validar_zona(zona_destino),
         :ok <- distintos(origen, destino),
         {:ok, desde} <- buscar(recursos, codigo, origen),
         {:ok, desde_nuevo} <- Recurso.restar(desde, cantidad, :transferencia_salida),
         {:ok, hacia_nuevo} <- recibir(recursos, desde, destino, cantidad, zona_destino) do
      nuevos =
        recursos
        |> Map.put(Recurso.clave(desde_nuevo), desde_nuevo)
        |> Map.put(Recurso.clave(hacia_nuevo), hacia_nuevo)

      {:reply, {:ok, %{origen: desde_nuevo, destino: hacia_nuevo}}, guardar(nuevos)}
    else
      {:error, _} = error -> {:reply, error, recursos}
    end
  end

  def handle_call({:obtener, codigo, ubicacion}, _from, recursos) do
    {:reply, buscar(recursos, codigo, ubicacion), recursos}
  end

  def handle_call({:listar, filtros}, _from, recursos) do
    lista =
      recursos
      |> Map.values()
      |> Enum.filter(&cumple_filtros?(&1, filtros))
      |> Enum.sort_by(&Recurso.clave/1)

    {:reply, lista, recursos}
  end

  def handle_call({:disponibilidad, clave, ubicacion, zona}, _from, recursos) do
    total =
      recursos
      |> Map.values()
      |> Enum.filter(fn r ->
        Recurso.coincide?(r, clave) and
          (is_nil(ubicacion) or Validacion.coincide?(r.ubicacion, ubicacion)) and
          (is_nil(zona) or Validacion.coincide?(r.zona, zona))
      end)
      |> Enum.reduce(0, fn r, acc -> acc + r.cantidad end)

    {:reply, total, recursos}
  end

  def handle_call({:criticos, umbral}, _from, recursos) do
    lista =
      recursos
      |> Map.values()
      |> Enum.filter(&(&1.cantidad <= umbral))
      |> Enum.sort_by(&{&1.cantidad, Recurso.clave(&1)})

    {:reply, lista, recursos}
  end

  # ========== Funciones auxiliares ==========

  defp buscar(recursos, codigo, ubicacion) do
    case Map.fetch(recursos, {codigo, ubicacion}) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, :no_existe}
    end
  end

  defp aplicar(recurso, :entrada, n), do: Recurso.sumar(recurso, n, :entrada)
  defp aplicar(recurso, :salida, n), do: Recurso.restar(recurso, n, :salida)

  # Recursos con existencias que coinciden con la clave, en orden estable
  defp candidatos(recursos, clave) do
    recursos
    |> Map.values()
    |> Enum.filter(&(&1.cantidad > 0 and Recurso.coincide?(&1, clave)))
    |> Enum.sort_by(&Recurso.clave/1)
  end

  # Recursiva de cola: va tomando de cada candidato hasta cubrir lo faltante.
  # Si se acaban los candidatos antes, no se toma nada (todo o nada).
  defp tomar(_candidatos, 0, acumulado), do: {:ok, Enum.reverse(acumulado)}
  defp tomar([], _faltante, _acumulado), do: {:error, :insuficiente}

  defp tomar([recurso | resto], faltante, acumulado) do
    n = min(recurso.cantidad, faltante)
    tomar(resto, faltante - n, [{recurso.codigo, recurso.ubicacion, n} | acumulado])
  end

  defp compatibles(candidatos, nil), do: {:ok, candidatos}

  defp compatibles(candidatos, tipo) do
    with {:ok, tipo} <- Validacion.atomo(tipo, Necesidad.tipos(), :tipo_invalido) do
      case Enum.filter(candidatos, &Recurso.compatible?(&1, tipo)) do
        [] when candidatos != [] -> {:error, :recurso_incompatible}
        lista -> {:ok, lista}
      end
    end
  end

  defp distintos(a, b) when a == b, do: {:error, :mismo_lugar}
  defp distintos(_a, _b), do: :ok

  # Suma al destino; si todavía no existe lo crea con los datos del origen
  defp recibir(recursos, desde, destino, cantidad, zona_destino) do
    case Map.fetch(recursos, {desde.codigo, destino}) do
      {:ok, existente} ->
        if is_nil(zona_destino) or Validacion.coincide?(existente.zona, zona_destino) do
          Recurso.sumar(existente, cantidad, :transferencia_entrada)
        else
          {:error, :zona_destino_distinta}
        end

      :error ->
        with {:ok, nuevo} <-
               Recurso.nuevo(desde.codigo, desde.nombre, desde.categoria, 0, desde.unidad, destino,
                 zona_destino || zona_ubicacion(recursos, destino) || desde.zona) do
          Recurso.sumar(nuevo, cantidad, :transferencia_entrada)
        end
    end
  end

  defp cumple_filtros?(recurso, filtros) do
    Enum.all?(filtros, fn
      {campo, valor} when campo in [:categoria, :ubicacion, :codigo, :zona] ->
        Validacion.coincide?(Map.fetch!(recurso, campo), valor)

      _otro ->
        true
    end)
  end

  defp crear_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona) do
    with {:ok, recurso} <- Recurso.nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona),
         :ok <- validar_zona(recurso.zona) do
      {:ok, recurso}
    end
  end

  defp validar_zona(nil), do: :ok
  defp validar_zona(zona) do
    Zonas.validar(zona)
  end

  defp zona_ubicacion(recursos, ubicacion) do
    Enum.find_value(recursos, fn {_, r} -> if r.ubicacion == ubicacion, do: r.zona end)
  end

  defp zona_albergue(destino) do
    with {:ok, destino} <- Validacion.texto(destino),
         {:ok, albergue} <- Albergues.consultar(destino) do
      albergue.zona
    else
      _ -> nil
    end
  end

  defp guardar(recursos) do
    filas =
      recursos
      |> Map.values()
      |> Enum.sort_by(&Recurso.clave/1)
      |> Enum.map(&Recurso.a_fila/1)

    Persistencia.guardar(:recursos, filas)
    recursos
  end
end
