defmodule Albergue do
  @moduledoc """
  Un albergue y sus reglas. Módulo puro.

  Los ocupantes se guardan en un `MapSet` de documentos: no admite
  repetidos (una persona no puede ingresar dos veces) y consultar si alguien
  está dentro es rápido. La ocupación nunca puede superar la capacidad.
  """

  @enforce_keys [:codigo, :nombre, :zona, :capacidad]
  defstruct [:codigo, :nombre, :zona, :capacidad, ocupantes: MapSet.new(), recursos: [], necesidades: []]

  @doc """
  Crea un albergue vacío. La capacidad debe ser un entero positivo.

  ## Ejemplo

      iex> {:ok, a} = Albergue.nuevo("A01", "Albergue Norte", "zona_norte", 150)
      iex> Albergue.cupos(a)
      150
  """
  @spec nuevo(term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(codigo, nombre, zona, capacidad) do
    with {:ok, codigo} <- Validacion.texto(codigo),
         {:ok, nombre} <- Validacion.texto(nombre),
         {:ok, zona} <- Validacion.texto(zona),
         {:ok, capacidad} <- Validacion.entero_positivo(capacidad) do
      {:ok, %__MODULE__{codigo: codigo, nombre: nombre, zona: zona, capacidad: capacidad}}
    end
  end

  @doc "Personas que hay actualmente."
  @spec ocupacion(%__MODULE__{}) :: non_neg_integer()
  def ocupacion(%__MODULE__{ocupantes: ocupantes}), do: MapSet.size(ocupantes)

  @doc "Cupos libres."
  @spec cupos(%__MODULE__{}) :: non_neg_integer()
  def cupos(%__MODULE__{} = a), do: a.capacidad - ocupacion(a)

  @doc "Porcentaje de ocupación (0.0 a 100.0)."
  @spec porcentaje(%__MODULE__{}) :: float()
  def porcentaje(%__MODULE__{} = a), do: Float.round(ocupacion(a) * 100 / a.capacidad, 1)

  @doc "Registra el ingreso de una persona. Errores: `:sin_cupo`, `:ya_registrado`."
  @spec ingresar(%__MODULE__{}, term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def ingresar(%__MODULE__{} = a, documento) do
    with {:ok, documento} <- Validacion.texto(documento) do
      cond do
        MapSet.member?(a.ocupantes, documento) -> {:error, :ya_registrado}
        cupos(a) <= 0 -> {:error, :sin_cupo}
        true -> {:ok, %{a | ocupantes: MapSet.put(a.ocupantes, documento)}}
      end
    end
  end

  @doc "Registra la salida de una persona. Error `:no_esta` si no estaba dentro."
  @spec salir(%__MODULE__{}, term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def salir(%__MODULE__{} = a, documento) do
    with {:ok, documento} <- Validacion.texto(documento) do
      if MapSet.member?(a.ocupantes, documento) do
        {:ok, %{a | ocupantes: MapSet.delete(a.ocupantes, documento)}}
      else
        {:error, :no_esta}
      end
    end
  end

  @doc "Asocia un recurso (`:recurso`) o una necesidad (`:necesidad`) al albergue, sin repetir."
  @spec asociar(%__MODULE__{}, :recurso | :necesidad, String.t()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def asociar(%__MODULE__{} = a, :recurso, id) do
    with {:ok, id} <- Validacion.texto(id), do: {:ok, %{a | recursos: Enum.uniq(a.recursos ++ [id])}}
  end

  def asociar(%__MODULE__{} = a, :necesidad, id) do
    with {:ok, id} <- Validacion.texto(id), do: {:ok, %{a | necesidades: Enum.uniq(a.necesidades ++ [id])}}
  end

  def asociar(%__MODULE__{}, _tipo, _id), do: {:error, :tipo_invalido}

  @doc "Resumen para mostrar al usuario (sin la lista de documentos)."
  @spec resumen(%__MODULE__{}) :: map()
  def resumen(%__MODULE__{} = a) do
    %{
      codigo: a.codigo,
      nombre: a.nombre,
      zona: a.zona,
      capacidad: a.capacidad,
      ocupacion: ocupacion(a),
      cupos: cupos(a),
      porcentaje: porcentaje(a),
      recursos: a.recursos,
      necesidades: a.necesidades
    }
  end

  # ---------- Persistencia ----------

  @doc "Convierte el albergue en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = a) do
    [
      Archivo.sanear(a.codigo),
      Archivo.sanear(a.nombre),
      Archivo.sanear(a.zona),
      to_string(a.capacidad),
      a.ocupantes |> Enum.sort() |> Enum.map(&Archivo.sanear_item/1) |> Archivo.lista_a_texto(),
      a.recursos |> Enum.map(&Archivo.sanear_item/1) |> Archivo.lista_a_texto(),
      a.necesidades |> Enum.map(&Archivo.sanear_item/1) |> Archivo.lista_a_texto()
    ]
  end

  @doc "Reconstruye un albergue desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([codigo, nombre, zona, capacidad, ocupantes, recursos, necesidades]) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: String.to_integer(capacidad),
      ocupantes: ocupantes |> Archivo.texto_a_lista() |> MapSet.new(),
      recursos: Archivo.texto_a_lista(recursos),
      necesidades: Archivo.texto_a_lista(necesidades)
    }
  end
end

