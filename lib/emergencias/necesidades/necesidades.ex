defmodule Necesidades do
  @moduledoc """
  Proceso que guarda las necesidades puntuales, siempre ordenadas por
  prioridad (la más crítica primero).

  ## Asignar un recurso

  `asignar/3` coordina dos procesos sin bloquear ninguno:

  1. reserva las unidades en `Inventario` (atómico: o se reservan todas o
     ninguna);
  2. registra la asignación en la necesidad;
  3. si el paso 2 falla (por ejemplo, otra solicitud ya completó la
     necesidad), devuelve las unidades con `Inventario.liberar/1`.

  Así el inventario nunca queda con unidades "perdidas".
  """
  use GenServer

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Registra una necesidad. El identificador (`N001`, `N002`...) se genera solo."
  @spec registrar(term(), term(), term(), term(), term(), term()) ::
          {:ok, %Necesidad{}} | {:error, atom()}
  def registrar(tipo, cantidad, prioridad, zona, descripcion, responsable) do
    GenServer.call(__MODULE__, {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable})
  end

  @doc """
  Lista necesidades ordenadas por prioridad.
  Filtros opcionales: `zona:`, `tipo:`, `prioridad:`, `estado:`.
  """
  @spec listar(keyword()) :: [%Necesidad{}]
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Necesidades pendientes, de la más crítica a la menos crítica."
  @spec pendientes() :: [%Necesidad{}]
  def pendientes, do: listar(estado: :pendiente)

  @doc "Busca una necesidad por su identificador."
  @spec obtener(String.t()) :: {:ok, %Necesidad{}} | {:error, :no_existe}
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})

  @doc """
  Asigna recursos (por código o categoría) a una necesidad.

  Errores posibles: `:no_existe`, `:estado_invalido`, `:excede_requerida`,
  `:insuficiente`, `:cantidad_invalida`.
  """
  @spec asignar(String.t(), String.t(), term()) :: {:ok, %Necesidad{}} | {:error, atom()}
  def asignar(id, clave_recurso, cantidad) do
    with {:ok, cantidad} <- Validacion.entero_positivo(cantidad),
         {:ok, necesidad} <- obtener(id),
         :ok <- verificar_asignable(necesidad, cantidad),
         {:ok, detalle} <- Inventario.reservar(clave_recurso, cantidad) do
      case GenServer.call(__MODULE__, {:registrar_asignacion, id, detalle}) do
        {:ok, _} = ok ->
          ok

        {:error, _} = error ->
          # Otra solicitud se adelantó: se devuelven las unidades reservadas
          Inventario.liberar(detalle)
          error
      end
    end
  end

  @doc "Cambia el estado respetando las transiciones válidas."
  @spec cambiar_estado(String.t(), term()) :: {:ok, %Necesidad{}} | {:error, atom()}
  def cambiar_estado(id, estado), do: GenServer.call(__MODULE__, {:cambiar_estado, id, estado})

  @doc "Cancela la necesidad y devuelve al inventario lo que tenía asignado."
  @spec cancelar(String.t()) :: {:ok, %Necesidad{}} | {:error, atom()}
  def cancelar(id) do
    with {:ok, necesidad} <- cambiar_estado(id, :cancelada) do
      Inventario.liberar(necesidad.asignaciones)
      {:ok, necesidad}
    end
  end

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    lista =
      :necesidades
      |> Persistencia.cargar()
      |> Enum.map(&Necesidad.desde_fila/1)
      |> Enum.reduce([], fn n, acc -> Necesidad.insertar_ordenado(acc, n) end)

    {:ok, lista}
  end

  @impl true
  def handle_call({:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable}, _from, lista) do
    case Necesidad.nuevo(siguiente_id(lista), tipo, cantidad, prioridad, zona, descripcion, responsable) do
      {:ok, necesidad} ->
        {:reply, {:ok, necesidad}, guardar(Necesidad.insertar_ordenado(lista, necesidad))}

      {:error, _} = error ->
        {:reply, error, lista}
    end
  end

  def handle_call({:listar, filtros}, _from, lista) do
    {:reply, Enum.filter(lista, &cumple_filtros?(&1, filtros)), lista}
  end

  def handle_call({:obtener, id}, _from, lista), do: {:reply, buscar(lista, id), lista}

  def handle_call({:registrar_asignacion, id, detalle}, _from, lista) do
    actualizar(lista, id, &Necesidad.asignar(&1, detalle))
  end

  def handle_call({:cambiar_estado, id, estado}, _from, lista) do
    actualizar(lista, id, &Necesidad.cambiar_estado(&1, estado))
  end

  # ========== Funciones auxiliares ==========

  defp verificar_asignable(%Necesidad{estado: :pendiente} = n, cantidad) do
    if cantidad <= Necesidad.faltante(n), do: :ok, else: {:error, :excede_requerida}
  end

  defp verificar_asignable(%Necesidad{}, _cantidad), do: {:error, :estado_invalido}

  defp buscar(lista, id) do
    case Enum.find(lista, &(&1.id == id)) do
      nil -> {:error, :no_existe}
      necesidad -> {:ok, necesidad}
    end
  end

  # Aplica una operación a una necesidad y, si salió bien, la guarda
  defp actualizar(lista, id, operacion) do
    with {:ok, necesidad} <- buscar(lista, id),
         {:ok, nueva} <- operacion.(necesidad) do
      reemplazada = Enum.map(lista, fn n -> if n.id == id, do: nueva, else: n end)
      {:reply, {:ok, nueva}, guardar(reemplazada)}
    else
      {:error, _} = error -> {:reply, error, lista}
    end
  end

  defp siguiente_id(lista) do
    maximo = lista |> Enum.map(&Necesidad.numero/1) |> Enum.max(fn -> 0 end)
    "N" <> String.pad_leading(Integer.to_string(maximo + 1), 3, "0")
  end

  defp cumple_filtros?(necesidad, filtros) do
    Enum.all?(filtros, fn
      {campo, valor} when campo in [:zona, :tipo, :prioridad, :estado] ->
        Validacion.coincide?(Map.fetch!(necesidad, campo), valor)

      _otro ->
        true
    end)
  end

  defp guardar(lista) do
    Persistencia.guardar(:necesidades, Enum.map(lista, &Necesidad.a_fila/1))
    lista
  end
end
