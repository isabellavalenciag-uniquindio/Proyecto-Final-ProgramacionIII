defmodule EmergenciasWeb.SesionController do
  use EmergenciasWeb, :controller
  alias Emergencias.SesionesWeb

  def crear(conn, %{"acceso" => datos}) when is_map(datos) do
    campos = ~w(usuario clave tipo zona nombre)
    args = Enum.map(campos, fn campo -> Map.get(datos, campo, "") end)
    [usuario, clave, tipo, zona, nombre] = args

    args = [
      usuario,
      clave,
      vacio(tipo, "ciudadano"),
      vacio(zona, "sin_zona"),
      vacio(nombre, usuario)
    ]

    case Comandos.ejecutar_operacion(:connect, args, Emergencias.nueva_sesion()) do
      {:ok, _, sesion} ->
        if anterior = get_session(conn, :token), do: SesionesWeb.cerrar(anterior)
        {:ok, token} = SesionesWeb.crear(sesion)

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:token, token)
        |> put_session(:live_socket_id, SesionesWeb.socket_id(token))
        |> redirect(to: "/")

      {:error, texto, _} ->
        conn |> put_flash(:error, texto) |> redirect(to: "/acceso")
    end
  end

  def crear(conn, _),
    do: conn |> put_flash(:error, "Completa tus datos de acceso.") |> redirect(to: "/acceso")

  def cerrar(conn, _) do
    SesionesWeb.cerrar(get_session(conn, :token))
    conn |> clear_session() |> configure_session(drop: true) |> redirect(to: "/acceso")
  end

  defp vacio(valor, defecto) when is_binary(valor) do
    if String.trim(valor) == "", do: defecto, else: valor
  end

  defp vacio(_, defecto), do: defecto
end
