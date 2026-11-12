defmodule Util2 do
  @moduledoc """
  Funciones auxiliares de propósito general para entrada y salida de datos,
  procesamiento de colecciones y conversión de sus elementos a texto.

  El módulo incluye funciones para:

  - leer datos desde teclado;
  - validar valores enteros, reales y booleanos;
  - ingresar colecciones de elementos;
  - mostrar mensajes y errores;
  - ordenar y filtrar colecciones;
  - convertir colecciones a una representación textual.


  """

  # -----------------------------------
  # Salida de datos
  # -----------------------------------

  @doc """
  Muestra un mensaje en la salida indicada.

  El segundo argumento determina si el contenido se envía a la salida
  estándar o a la salida de errores.

  ## Parámetros

  - `mensaje`: contenido que se desea mostrar.
  - `:mensaje`: muestra el contenido en la salida estándar.
  - `:error`: muestra el contenido en la salida estándar de errores.

  ## Ejemplos

      Util2.mostrar("Hola Mundo", :mensaje)

      Util2.mostrar("Operación incorrecta", :error)

  También puede utilizarse mediante el operador `|>`:

      "Hola Mundo"
      |> Util2.mostrar(:mensaje)

      "Operación incorrecta"
      |> Util2.mostrar(:error)
  """
  def mostrar(mensaje, :mensaje), do: IO.puts(mensaje)
  def mostrar(mensaje, :error), do: IO.puts(:standard_error, mensaje)

  # -----------------------------------
  # Entrada de datos
  # -----------------------------------

  @doc """
  Lee desde teclado un dato o una colección de datos.

  El comportamiento de la función depende del segundo argumento.

  ## Entrada de un dato

  Cuando el primer argumento es una pregunta, pueden utilizarse los
  siguientes tipos:

  - `:texto`: lee una cadena de caracteres.
  - `:entero`: lee y valida un número entero.
  - `:real`: lee y valida un número real.
  - `:boolean`: lee una respuesta `s` o `n` y retorna `true` o `false`.

  Por ejemplo:

      Util2.ingresar("Ingrese el nombre: ", :texto)

      Util2.ingresar("Ingrese la edad: ", :entero)

      Util2.ingresar("Ingrese la altura: ", :real)

      Util2.ingresar("¿Desea continuar (s/n)? ", :boolean)

  También puede utilizarse mediante el operador `|>`:

      "Ingrese la edad: "
      |> Util2.ingresar(:entero)

  ## Entrada de una colección

  Para ingresar una colección de elementos puede proporcionarse una
  función de aridad cero encargada de leer cada elemento:

      Util2.ingresar(&Reserva.ingresar/0, :coleccion)

  La función preguntará después de cada elemento si existen más datos.

  También existen formas abreviadas para colecciones de tipos básicos:

  - `:coleccion_textos`
  - `:coleccion_enteros`
  - `:coleccion_reales`

  Por ejemplo:

      Util2.ingresar("Ingrese un número: ", :coleccion_enteros)

      Util2.ingresar("Ingrese un nombre: ", :coleccion_textos)
  """
  def ingresar(pregunta, :coleccion_reales) do
    ingresar(fn -> ingresar(pregunta, :real) end, :coleccion)
  end

  def ingresar(pregunta, :coleccion_enteros) do
    ingresar(fn -> ingresar(pregunta, :entero) end, :coleccion)
  end

  def ingresar(pregunta, :coleccion_textos) do
    ingresar(fn -> ingresar(pregunta, :texto) end, :coleccion)
  end

  def ingresar(ingresar_elemento, :coleccion) do
    ingresar_coleccion(ingresar_elemento, [])
  end

  def ingresar(pregunta, :boolean) do
    ingresar(
      pregunta,
      fn texto ->
        case String.downcase(texto) do
          "s" -> {true, ""}
          "n" -> {false, ""}
          _ -> :error
        end
      end,
      :boolean
    )
  end

  def ingresar(pregunta, :real) do
    ingresar(pregunta, &Float.parse/1, :real)
  end

  def ingresar(pregunta, :entero) do
    ingresar(pregunta, &Integer.parse/1, :entero)
  end

  def ingresar(mensaje, :texto) do
    mensaje
    |> IO.gets()
    |> String.trim()
  end

  # -----------------------------------
  # Operaciones sobre colecciones
  # -----------------------------------

  @doc """
  Ordena los elementos de una colección.

  Por defecto, los elementos se ordenan de forma ascendente utilizando
  como criterio el propio elemento.

  ## Parámetros

  - `coleccion`: colección que se desea ordenar.
  - `sentido`: orden `:asc` o `:desc`. Su valor por defecto es `:asc`.
  - `obtener_campo`: función que obtiene el valor utilizado como criterio
    de ordenamiento. Por defecto se utiliza `& &1`.

  La función criterio también puede retornar una tupla para ordenar por
  varios campos.

  ## Ejemplos

  Orden ascendente:

      Util2.ordenar(coleccion)

  Orden descendente:

      Util2.ordenar(coleccion, :desc)

  Si los elementos son estructuras con los campos `nombre` y `edad`,
  pueden ordenarse por edad:

      Util2.ordenar(coleccion, :asc, & &1.edad)

  Para ordenar primero por nombre y, en caso de empate, por edad:

      Util2.ordenar(coleccion, :asc, &{&1.nombre, &1.edad})
  """
  def ordenar(coleccion, sentido \\ :asc, obtener_campo \\ & &1) do
    Enum.sort_by(coleccion, obtener_campo, sentido)
  end

  @doc """
  Filtra una colección de cadenas conservando aquellas cuya longitud
  sea menor o igual al valor indicado.

  ## Parámetros

  - `coleccion`: colección de cadenas que se desea filtrar.
  - `longitud`: longitud máxima permitida.

  ## Ejemplo

  Obtiene las cadenas de longitud menor o igual a `3`:

      Util2.aplicar_filtro_longitud(coleccion, 3)
  """
  def aplicar_filtro_longitud(coleccion, longitud) do
    aplicar_filtro(coleccion, &(String.length(&1) <= longitud))
  end

  @doc """
  Filtra una colección de cadenas conservando aquellas que comienzan
  con una subcadena determinada.

  ## Parámetros

  - `coleccion`: colección de cadenas que se desea filtrar.
  - `inicia`: subcadena con la que deben comenzar los elementos seleccionados.

  ## Ejemplo

  Obtiene las cadenas que comienzan con `"Ana"`:

      Util2.aplicar_filtro_inicial(coleccion, "Ana")
  """
  def aplicar_filtro_inicial(coleccion, inicia) do
    aplicar_filtro(coleccion, &String.starts_with?(&1, inicia))
  end

  @doc """
  Filtra una colección de cadenas conservando aquellas que cumplan con
  la función de filtro.

  ## Parámetros

  - `coleccion`: colección de cadenas que se desea filtrar.
  - `filtro`: función para filtrar los elementos.

  ## Ejemplo

  Obtiene las cadenas que comienzan con `"Ana"`:

      Util2.aplicar_filtro(coleccion, &String.starts_with?(&1, "Ana"))
  """
  def aplicar_filtro(coleccion, filtro) do
    Enum.filter(coleccion, filtro)
  end

  @doc """
  Aplica un formato textual a cada elemento de una colección.

  Por defecto, cada elemento se representa como un ítem de una lista
  precedido por un guion.

  ## Parámetros

  - `coleccion`: colección cuyos elementos se desean convertir.
  - `formato`: función que recibe un elemento y retorna su representación
    textual. Por defecto:

        fn elemento -> " - \#{elemento}\\n" end

  ## Ejemplos

  Con el formato predeterminado:

      Util2.convertir_coleccion_mensaje(coleccion)

  produce una representación equivalente a:

      - Elemento 1
      - Elemento 2
      - Elemento 3

  Para separar los elementos mediante tabuladores:

      Util2.convertir_coleccion_mensaje(
        coleccion,
        fn elemento -> "\#{elemento}\\t" end
      )
  """
  def convertir_coleccion_mensaje(
        coleccion,
        formato \\ fn elemento -> " - #{elemento}\n" end
      ) do
    Enum.map(coleccion, formato)
  end

  # -----------------------------------
  # Funciones auxiliares privadas
  # -----------------------------------

  # Ingresa recursivamente los elementos de una colección.
  #
  # `ingresar_elemento` es una función de aridad cero encargada de
  # obtener cada elemento y `lista_actual` actúa como acumulador.
  defp ingresar_coleccion(ingresar_elemento, lista_actual) do
    elemento = ingresar_elemento.()
    nueva_lista = [elemento | lista_actual]

    case ingresar("\n¿Hay más datos (s/n)? ", :boolean) do
      true ->
        ingresar_coleccion(ingresar_elemento, nueva_lista)

      false ->
        Enum.reverse(nueva_lista)
    end
  end

  # Lee y valida un dato utilizando la función `parser`.
  #
  # Si el valor no puede interpretarse como el tipo solicitado,
  # muestra un mensaje de error y solicita nuevamente el dato.
  defp ingresar(pregunta, parser, tipo_dato) do
    resultado =
      pregunta
      |> ingresar(:texto)
      |> parser.()

    case resultado do
      {valor, ""} ->
        valor

      _ ->
        mostrar(
          "El valor ingresado no es válido para el tipo #{tipo_dato}. Intente nuevamente.\n",
          :error
        )

        ingresar(pregunta, tipo_dato)
    end
  end
end
