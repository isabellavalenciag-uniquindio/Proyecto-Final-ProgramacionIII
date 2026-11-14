defmodule Mensaje do
  @moduledoc """
  Mensaje dirigido a una persona (por su documento). Módulo puro.

  Estados: `:pendiente` (todavía no se entrega) y `:entregado`.
  """

  @enforce_keys [:id, :fecha, :remitente, :destinatario, :contenido]
  defstruct [:id, :fecha, :remitente, :destinatario, :contenido, estado: :pendiente]

  @max_contenido 500

  @doc """
  Crea un mensaje pendiente. El contenido no puede estar vacío ni pasar de 500 caracteres.

  ## Ejemplo

      iex> {:ok, m} = Mensaje.nuevo(1, "ana", "123", "Estoy bien")
      iex> m.estado
      :pendiente
  """
  @spec nuevo(integer(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(id, remitente, destinatario, contenido) do
    with {:ok, remitente} <- Validacion.texto(remitente),
         {:ok, destinatario} <- Validacion.texto(destinatario),
         {:ok, contenido} <- validar_contenido(contenido) do
      {:ok,
       %__MODULE__{
         id: id,
         fecha: Persona.ahora(),
         remitente: remitente,
         destinatario: destinatario,
         contenido: contenido
       }}
    end
  end

  @doc "Marca el mensaje como entregado. No se puede entregar dos veces."
  @spec marcar_entregado(%__MODULE__{}) :: {:ok, %__MODULE__{}} | {:error, :ya_entregado}
  def marcar_entregado(%__MODULE__{} = m), do: cambiar_estado(m, :entregado)

  @doc "Marca explícitamente un mensaje como pendiente o entregado."
  @spec cambiar_estado(%__MODULE__{}, term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def cambiar_estado(%__MODULE__{} = m, estado) do
    with {:ok, estado} <- Validacion.atomo(estado, [:pendiente, :entregado], :estado_invalido) do
      cond do
        estado == :entregado and m.estado == :entregado -> {:error, :ya_entregado}
        estado == m.estado -> {:error, :mismo_estado}
        true -> {:ok, %{m | estado: estado}}
      end
    end
  end

  defp validar_contenido(contenido) do
    with {:ok, texto} <- Validacion.texto(contenido) do
      if String.length(texto) <= @max_contenido, do: {:ok, texto}, else: {:error, :mensaje_largo}
    end
  end

  # ---------- Persistencia ----------

  @doc "Convierte el mensaje en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = m) do
    [
      to_string(m.id),
      m.fecha,
      Archivo.sanear(m.remitente),
      Archivo.sanear(m.destinatario),
      Archivo.sanear(m.contenido),
      to_string(m.estado)
    ]
  end

  @doc "Reconstruye un mensaje desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([id, fecha, remitente, destinatario, contenido, estado]) do
    %__MODULE__{
      id: String.to_integer(id),
      fecha: fecha,
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido,
      estado: if(estado == "entregado", do: :entregado, else: :pendiente)
    }
  end
end
