defmodule Usuario do
  @moduledoc """
  Un usuario del sistema y sus validaciones. Módulo puro.

  La contraseña nunca se guarda en claro: se guarda su hash SHA-256.
  Tipos de usuario: `:ciudadano`, `:voluntario`, `:coordinador`, `:administrador`.
  """

  @enforce_keys [:usuario, :clave_hash, :nombre, :tipo, :zona]
  defstruct [:usuario, :clave_hash, :nombre, :tipo, :zona]

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]
  @clave_minima 4

  @doc "Tipos de usuario válidos."
  def tipos, do: @tipos

  @doc """
  Crea un usuario validando todos los datos. El nombre de usuario se guarda en
  minúsculas y solo admite letras, números, `.`, `_` y `-`.

  ## Ejemplo

      iex> {:ok, u} = Usuario.nuevo("Laura", "1234", "Laura Pérez", "coordinador", "centro")
      iex> {u.usuario, u.tipo}
      {"laura", :coordinador}
  """
  @spec nuevo(term(), term(), term(), term(), term()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def nuevo(usuario, clave, nombre, tipo, zona) do
    with {:ok, usuario} <- validar_usuario(usuario),
         {:ok, clave} <- validar_clave(clave),
         {:ok, nombre} <- Validacion.texto(nombre),
         {:ok, tipo} <- Validacion.atomo(tipo, @tipos, :tipo_invalido),
         {:ok, zona} <- Validacion.texto(zona) do
      {:ok, %__MODULE__{usuario: usuario, clave_hash: hash(clave), nombre: nombre, tipo: tipo, zona: zona}}
    end
  end

  @doc "Pasa el nombre de usuario a su forma canónica (sin espacios, en minúsculas)."
  @spec normalizar_usuario(term()) :: String.t()
  def normalizar_usuario(usuario) when is_binary(usuario), do: usuario |> String.trim() |> String.downcase()
  def normalizar_usuario(_), do: ""

  @doc "Indica si la contraseña corresponde al usuario."
  @spec verificar_clave(%__MODULE__{}, term()) :: boolean()
  def verificar_clave(%__MODULE__{clave_hash: hash}, clave) when is_binary(clave), do: hash == hash(clave)
  def verificar_clave(%__MODULE__{}, _clave), do: false

  defp validar_usuario(usuario) do
    nombre = normalizar_usuario(usuario)

    if nombre != "" and String.match?(nombre, ~r/^[\p{L}\p{N}._-]+$/u),
      do: {:ok, nombre},
      else: {:error, :usuario_invalido}
  end

  defp validar_clave(clave) when is_binary(clave) do
    if String.length(clave) >= @clave_minima, do: {:ok, clave}, else: {:error, :clave_corta}
  end

  defp validar_clave(_), do: {:error, :clave_corta}

  defp hash(clave), do: :crypto.hash(:sha256, clave) |> Base.encode16(case: :lower)

  # ---------- Persistencia ----------

  @doc "Convierte el usuario en una fila de texto para el CSV."
  @spec a_fila(%__MODULE__{}) :: [String.t()]
  def a_fila(%__MODULE__{} = u) do
    [u.usuario, u.clave_hash, Archivo.sanear(u.nombre), to_string(u.tipo), Archivo.sanear(u.zona)]
  end

  @doc "Reconstruye un usuario desde una fila del CSV."
  @spec desde_fila([String.t()]) :: %__MODULE__{}
  def desde_fila([usuario, hash, nombre, tipo, zona]) do
    %__MODULE__{
      usuario: usuario,
      clave_hash: hash,
      nombre: nombre,
      tipo: Enum.find(@tipos, &(Atom.to_string(&1) == tipo)),
      zona: zona
    }
  end
end
