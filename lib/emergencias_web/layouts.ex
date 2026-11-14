defmodule EmergenciasWeb.Layouts do
  use EmergenciasWeb, :html
  embed_templates "layouts/*"
end

defmodule EmergenciasWeb.ErrorHTML do
  def render("404.html", _), do: "Esta página no existe. Vuelve al inicio de NEXO."
  def render(_, _), do: "No pudimos completar esta solicitud. Intenta nuevamente."
end
