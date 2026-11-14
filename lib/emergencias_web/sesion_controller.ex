defmodule EmergenciasWeb.SesionController do
  use EmergenciasWeb, :controller
  alias Emergencias.SesionesWeb

  def crear(conn, %{"acceso" => datos}) when is_map(datos) do
    case acceder(datos) do
      {:ok, usuario} ->
        sesion = %{usuario: usuario}
        Usuarios.registrar_actividad(usuario.usuario, "connect #{usuario.usuario}")
        if anterior = get_session(conn, :token), do: SesionesWeb.cerrar(anterior)
        {:ok, token} = SesionesWeb.crear(sesion)

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:token, token)
        |> put_session(:live_socket_id, SesionesWeb.socket_id(token))
        |> redirect(to: "/")

      {:error, razon} ->
        destino = if datos["modo"] == "registro", do: "/acceso?modo=registro", else: "/acceso"
        conn |> put_flash(:error, mensaje_error(razon)) |> redirect(to: destino)
    end
  end

  def crear(conn, _),
    do: conn |> put_flash(:error, "Completa tus datos de acceso.") |> redirect(to: "/acceso")

  def cerrar(conn, _) do
    SesionesWeb.cerrar(get_session(conn, :token))
    conn |> clear_session() |> configure_session(drop: true) |> redirect(to: "/acceso")
  end

  defp acceder(%{"modo" => "registro"} = datos) do
    Usuarios.registrar_y_conectar(
      Map.get(datos, "usuario", ""),
      Map.get(datos, "clave", ""),
      Map.get(datos, "nombre", ""),
      vacio(Map.get(datos, "tipo", ""), "ciudadano"),
      vacio(Map.get(datos, "zona", ""), "sin_zona")
    )
  end

  defp acceder(datos) do
    if Map.get(datos, "modo", "ingreso") == "ingreso" do
      Usuarios.autenticar(Map.get(datos, "usuario", ""), Map.get(datos, "clave", ""))
    else
      {:error, :tipo_invalido}
    end
  end

  defp mensaje_error(:credenciales_invalidas),
    do: "Usuario o contraseña incorrectos. Verifica tus datos o usa Crear acceso."

  defp mensaje_error(:duplicado),
    do: "Ese usuario ya está registrado. Usa Ingresar con su contraseña."

  defp mensaje_error(razon), do: Comandos.mensaje_error(razon)

  defp vacio(valor, defecto) when is_binary(valor) do
    if String.trim(valor) == "", do: defecto, else: valor
  end

  defp vacio(valor, _defecto), do: valor
end
