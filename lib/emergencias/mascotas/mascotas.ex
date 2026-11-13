defmodule Mascotas do
  @moduledoc """
  Proceso que guarda los reportes de mascotas perdidas y encontradas.

  El cálculo de coincidencias **no se hace dentro del proceso** (lo
  bloquearía): `coincidencias/2` lee la lista, calcula en el proceso que
  llama (en paralelo con `Task.async_stream` por defecto) y solo vuelve al
  proceso para marcar los reportes como posible coincidencia.
  """
  use GenServer

  # ========== API del cliente ==========

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Registra un reporte. El identificador (`M001`, `M002`...) se genera solo."
  @spec reportar(term(), term(), term(), term(), term(), term(), term(), term()) ::
          {:ok, %Mascota{}} | {:error, atom()}
  def reportar(tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas \\ "") do
    GenServer.call(__MODULE__, {:reportar, {tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas}})
  end

  @doc "Lista reportes. Filtros opcionales: `especie:`, `zona:`, `estado:`, `tipo:`."
  @spec listar(keyword()) :: [%Mascota{}]
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Busca un reporte por su identificador."
  @spec obtener(String.t()) :: {:ok, %Mascota{}} | {:error, :no_existe}
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})

  @doc """
  Busca posibles coincidencias entre perdidas y encontradas y marca esos
  reportes como `:posible_coincidencia`. `modo` es `:paralelo` o `:secuencial`.
  """
  @spec coincidencias(:paralelo | :secuencial, non_neg_integer()) :: [map()]
  def coincidencias(modo \\ :paralelo, umbral \\ Mascota.umbral()) do
    lista = listar()

    pares =
      case modo do
        :paralelo -> Mascota.coincidencias_paralelo(lista, umbral)
        :secuencial -> Mascota.coincidencias(lista, umbral)
      end

    ids = Enum.flat_map(pares, fn p -> [p.perdida, p.encontrada] end)
    :ok = GenServer.call(__MODULE__, {:marcar_posibles, ids})
    pares
  end

  @doc """
  Confirma una coincidencia y cierra **ambos** reportes. Acepta los
  identificadores en cualquier orden. Errores: `:no_existe`, `:par_invalido`,
  `:especie_distinta`, `:ya_resuelta`.
  """
  @spec confirmar(String.t(), String.t()) :: {:ok, %{perdida: %Mascota{}, encontrada: %Mascota{}}} | {:error, atom()}
  def confirmar(id_a, id_b), do: GenServer.call(__MODULE__, {:confirmar, id_a, id_b})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    mascotas = :mascotas |> Persistencia.cargar() |> Enum.map(&Mascota.desde_fila/1) |> Map.new(&{&1.id, &1})
    {:ok, mascotas}
  end

  @impl true
  def handle_call({:reportar, {tipo, especie, nombre, color, tamano, zona, contacto, caract}}, _from, mascotas) do
    case Mascota.nuevo(siguiente_id(mascotas), tipo, especie, nombre, color, tamano, zona, contacto, caract) do
      {:ok, mascota} -> {:reply, {:ok, mascota}, guardar(Map.put(mascotas, mascota.id, mascota))}
      {:error, _} = error -> {:reply, error, mascotas}
    end
  end

  def handle_call({:listar, filtros}, _from, mascotas) do
    lista =
      mascotas
      |> Map.values()
      |> Enum.filter(fn m -> Enum.all?(filtros, &Mascota.cumple?(m, &1)) end)
      |> Enum.sort_by(& &1.id)

    {:reply, lista, mascotas}
  end

  def handle_call({:obtener, id}, _from, mascotas), do: {:reply, buscar(mascotas, id), mascotas}

  def handle_call({:marcar_posibles, ids}, _from, mascotas) do
    nuevas =
      Enum.reduce(ids, mascotas, fn id, acc ->
        case Map.fetch(acc, id) do
          {:ok, m} -> Map.put(acc, id, Mascota.marcar_posible(m))
          :error -> acc
        end
      end)

    {:reply, :ok, guardar(nuevas)}
  end

  def handle_call({:confirmar, id_a, id_b}, _from, mascotas) do
    with {:ok, a} <- buscar(mascotas, id_a),
         {:ok, b} <- buscar(mascotas, id_b),
         {perdida, encontrada} = ordenar_par(a, b),
         :ok <- validar_par(perdida, encontrada),
         {:ok, perdida_cerrada} <- Mascota.resolver(perdida, encontrada.id),
         {:ok, encontrada_cerrada} <- Mascota.resolver(encontrada, perdida.id) do
      nuevas =
        mascotas
        |> Map.put(perdida_cerrada.id, perdida_cerrada)
        |> Map.put(encontrada_cerrada.id, encontrada_cerrada)

      {:reply, {:ok, %{perdida: perdida_cerrada, encontrada: encontrada_cerrada}}, guardar(nuevas)}
    else
      {:error, _} = error -> {:reply, error, mascotas}
    end
  end

  # ========== Funciones auxiliares ==========

  defp buscar(mascotas, id) do
    case Map.fetch(mascotas, to_string(id) |> String.trim() |> String.upcase()) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, :no_existe}
    end
  end

  defp ordenar_par(%Mascota{tipo: :encontrada} = a, %Mascota{tipo: :perdida} = b), do: {b, a}
  defp ordenar_par(a, b), do: {a, b}

  defp validar_par(%Mascota{tipo: :perdida} = p, %Mascota{tipo: :encontrada} = e) do
    if Validacion.coincide?(p.especie, e.especie), do: :ok, else: {:error, :especie_distinta}
  end

  defp validar_par(_a, _b), do: {:error, :par_invalido}

  defp siguiente_id(mascotas) do
    maximo =
      mascotas |> Map.keys() |> Enum.map(&(&1 |> String.trim_leading("M") |> String.to_integer())) |> Enum.max(fn -> 0 end)

    "M" <> String.pad_leading(Integer.to_string(maximo + 1), 3, "0")
  end

  defp guardar(mascotas) do
    filas = mascotas |> Map.values() |> Enum.sort_by(& &1.id) |> Enum.map(&Mascota.a_fila/1)
    Persistencia.guardar(:mascotas, filas)
    mascotas
  end
end
