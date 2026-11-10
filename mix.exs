defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # La aplicación arranca el supervisor raíz (Emergencias.Application)
  def application do
    [
      mod: {Emergencias.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps, do: []
end

