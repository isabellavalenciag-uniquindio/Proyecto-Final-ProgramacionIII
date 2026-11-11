defmodule Validacion do
  @moduledoc """
  Validaciones y normalización de las entradas del usuario.

  Todas las funciones son puras y retornan `{:ok, valor}` o `{:error, razon}`,
  de modo que ninguna entrada inválida llega a modificar el estado.
  """

  @doc """
  Convierte un texto (o átomo) en uno de los átomos válidos.
  Ignora mayúsculas, tildes y espacios: `"Crítica"` equivale a `:critica`.

  ## Ejemplos

      iex> Validacion.atomo("Crítica", [:critica, :alta], :prioridad_invalida)
      {:ok, :critica}

      iex> Validacion.atomo("xyz", [:critica, :alta], :prioridad_invalida)
      {:error, :prioridad_invalida}
  """
  @spec atomo(term(), [atom()], atom()) :: {:ok, atom()} | {:error, atom()}
  def atomo(valor, validos, error \\ :invalido)

  def atomo(valor, validos, error) when is_atom(valor) and not is_nil(valor) do
    if valor in validos, do: {:ok, valor}, else: {:error, error}
  end

  def atomo(valor, validos, error) when is_binary(valor) do
    case Enum.find(validos, fn a -> coincide?(Atom.to_string(a), valor) end) do
      nil -> {:error, error}
      atomo -> {:ok, atomo}
    end
  end

  def atomo(_valor, _validos, error), do: {:error, error}

  @doc "Indica si dos valores son iguales sin distinguir mayúsculas, tildes ni espacios."
  @spec coincide?(term(), term()) :: boolean()
  def coincide?(a, b), do: normalizar(a) == normalizar(b)

  @doc "Pasa a minúsculas, quita tildes y cambia espacios por `_`."
  @spec normalizar(term()) :: String.t()
  def normalizar(valor) do
    valor
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, "_")
  end

  @doc "Valida un entero mayor que cero (acepta también un texto numérico)."
  @spec entero_positivo(term()) :: {:ok, pos_integer()} | {:error, :cantidad_invalida}
  def entero_positivo(n) when is_integer(n) and n > 0, do: {:ok, n}
  def entero_positivo(n) when is_binary(n), do: n |> parsear() |> entero_positivo()
  def entero_positivo(_), do: {:error, :cantidad_invalida}

  @doc "Valida un entero mayor o igual que cero (acepta también un texto numérico)."
  @spec entero_no_negativo(term()) :: {:ok, non_neg_integer()} | {:error, :cantidad_invalida}
  def entero_no_negativo(n) when is_integer(n) and n >= 0, do: {:ok, n}
  def entero_no_negativo(n) when is_binary(n), do: n |> parsear() |> entero_no_negativo()
  def entero_no_negativo(_), do: {:error, :cantidad_invalida}

  @doc "Valida un texto no vacío y lo devuelve sin espacios en los extremos."
  @spec texto(term()) :: {:ok, String.t()} | {:error, :texto_vacio}
  def texto(valor) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, :texto_vacio}
      limpio -> {:ok, limpio}
    end
  end

  def texto(_), do: {:error, :texto_vacio}

  defp parsear(texto) do
    case Integer.parse(String.trim(texto)) do
      {n, ""} -> n
      _ -> :error
    end
  end
end
