defmodule Archivo do
  @moduledoc """
  Lectura y escritura de archivos de texto plano (CSV con separador `|`).

  Es el único módulo que toca el disco. Cada entidad se guarda en
  `data/<entidad>.csv`, una línea por registro. Las listas internas de un
  campo se separan con `;`. No lleva encabezado.

  Se eligió `|` porque casi nunca aparece en el texto de un usuario y evita
  confundirlo con la coma de las descripciones. Para que los datos no rompan
  el formato, `sanear/1` y `sanear_item/1` reemplazan los caracteres
  reservados antes de escribir.

  En las pruebas se desactiva con `config :emergencias, persistir: false`.
  """

  @separador "|"

  @doc "Carpeta donde se guardan los datos."
  @spec directorio() :: String.t()
  def directorio do
    Application.get_env(:emergencias, :datos_dir, Path.join(File.cwd!(), "data"))
  end

  @doc "Indica si la persistencia está activa."
  @spec persistir?() :: boolean()
  def persistir?, do: Application.get_env(:emergencias, :persistir, true)

  @doc "Ruta del archivo de una entidad."
  @spec ruta(atom()) :: String.t()
  def ruta(entidad), do: Path.join(directorio(), "#{entidad}.csv")

  @doc "Lee todas las filas de una entidad (lista vacía si no hay archivo)."
  @spec leer(atom()) :: [[String.t()]]
  def leer(entidad) do
    if persistir?(), do: leer_en(ruta(entidad)), else: []
  end

  @doc "Reemplaza el archivo de una entidad por las filas dadas."
  @spec escribir(atom(), [[term()]]) :: :ok | {:error, term()}
  def escribir(entidad, filas) do
    if persistir?(), do: escribir_en(ruta(entidad), filas), else: :ok
  end

  @doc "Inserta o reemplaza una fila cuya primera columna es la clave."
  @spec guardar_fila(atom(), [term()]) :: :ok | {:error, term()}
  def guardar_fila(entidad, fila) do
    if persistir?() do
      ruta = ruta(entidad)
      escribir_en(ruta, upsert(leer_en(ruta), Enum.map(fila, &to_string/1)))
    else
      :ok
    end
  end

  @doc """
  Reemplaza la fila con la misma clave (primera columna) o la agrega al final.

  ## Ejemplo

      iex> Archivo.upsert([["a", "1"], ["b", "2"]], ["b", "9"])
      [["a", "1"], ["b", "9"]]
  """
  @spec upsert([[String.t()]], [String.t()]) :: [[String.t()]]
  def upsert(filas, [clave | _] = fila) do
    if Enum.any?(filas, fn [k | _] -> k == clave end) do
      Enum.map(filas, fn
        [^clave | _] -> fila
        otra -> otra
      end)
    else
      filas ++ [fila]
    end
  end

  @doc "Lee las filas de un archivo cualquiera, perezosamente (`File.stream!`)."
  @spec leer_en(String.t()) :: [[String.t()]]
  def leer_en(ruta) do
    if File.exists?(ruta) do
      ruta
      |> File.stream!()
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.map(&String.trim_trailing(&1, "\r"))
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&String.split(&1, @separador))
    else
      []
    end
  end

  @doc """
  Escribe las filas en un archivo. Escribe primero en un temporal y luego lo
  renombra, así un fallo a la mitad no deja el archivo corrupto.
  """
  @spec escribir_en(String.t(), [[term()]]) :: :ok | {:error, term()}
  def escribir_en(ruta, filas) do
    contenido = Enum.map_join(filas, "", fn fila -> Enum.join(fila, @separador) <> "\n" end)
    temporal = ruta <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- File.write(temporal, contenido) do
      File.rename(temporal, ruta)
    end
  end

  @doc "Quita del texto los caracteres que rompen el formato de una línea."
  @spec sanear(term()) :: String.t()
  def sanear(texto) do
    texto |> to_string() |> String.replace(["|", "\n", "\r"], " ") |> String.trim()
  end

  @doc "Como `sanear/1`, pero también quita `;` y `:` (usados dentro de las listas)."
  @spec sanear_item(term()) :: String.t()
  def sanear_item(texto) do
    texto |> to_string() |> String.replace(["|", "\n", "\r", ";", ":"], "-") |> String.trim()
  end

  @doc "Une los elementos de una lista en un solo campo."
  @spec lista_a_texto([term()]) :: String.t()
  def lista_a_texto(items), do: Enum.join(items, ";")

  @doc "Separa un campo en su lista de elementos."
  @spec texto_a_lista(String.t()) :: [String.t()]
  def texto_a_lista(""), do: []
  def texto_a_lista(texto), do: String.split(texto, ";")
end
