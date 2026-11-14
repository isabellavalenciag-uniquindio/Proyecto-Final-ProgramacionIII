defmodule Albergues do
  @moduledoc """
  Fachada para trabajar con los albergues sin conocer los procesos que hay
  detrás. Los consultas de varios albergues se hacen en paralelo con
  `Task.async_stream/3`.
  """

  @doc "Registra un albergue nuevo y le crea su proceso."
  @spec registrar(term(), term(), term(), term()) :: {:ok, map()} | {:error, atom()}
  def registrar(codigo, nombre, zona, capacidad) do
    with {:ok, albergue} <- Albergue.nuevo(codigo, nombre, zona, capacidad),
         :ok <- Zonas.validar(albergue.zona),
         {:ok, _pid} <- AlbergueSupervisor.iniciar_albergue(albergue) do
      {:ok, Albergue.resumen(albergue)}
    end
  end

  @doc "Recrea los procesos de los albergues guardados. Se llama al iniciar la aplicación."
  @spec cargar() :: :ok
  def cargar do
    :albergues
    |> Persistencia.cargar()
    |> Enum.each(fn fila -> fila |> Albergue.desde_fila() |> AlbergueSupervisor.iniciar_albergue() end)
  end

  @doc "Registra el ingreso de una persona (por documento)."
  @spec ingresar(String.t(), term()) :: {:ok, map()} | {:error, atom()}
  def ingresar(codigo, documento), do: AlbergueProceso.ingresar(codigo, documento)

  @doc "Registra la salida de una persona."
  @spec salir(String.t(), term()) :: {:ok, map()} | {:error, atom()}
  def salir(codigo, documento), do: AlbergueProceso.salir(codigo, documento)

  @doc "Consulta cupos y ocupación de un albergue."
  @spec consultar(String.t()) :: {:ok, map()} | {:error, :no_existe}
  def consultar(codigo) do
    with {:ok, albergue} <- AlbergueProceso.consultar(codigo), do: {:ok, Albergue.resumen(albergue)}
  end

  @doc "Asocia un recurso al albergue."
  @spec asociar_recurso(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def asociar_recurso(codigo, id), do: AlbergueProceso.asociar(codigo, :recurso, id)

  @doc "Asocia una necesidad al albergue."
  @spec asociar_necesidad(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def asociar_necesidad(codigo, id), do: AlbergueProceso.asociar(codigo, :necesidad, id)

  @doc "Resumen de todos los albergues, consultados en paralelo."
  @spec listar() :: [map()]
  def listar do
    AlbergueProceso.codigos()
    |> Task.async_stream(&consultar/1, timeout: 5_000)
    |> Enum.flat_map(fn
      {:ok, {:ok, resumen}} -> [resumen]
      _ -> []
    end)
  end

  @doc "Los `n` albergues con mayor porcentaje de ocupación."
  @spec ranking(pos_integer()) :: [map()]
  def ranking(n \\ 5) do
    listar() |> Enum.sort_by(& &1.porcentaje, :desc) |> Enum.take(n)
  end
end
