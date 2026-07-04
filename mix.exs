defmodule Pulsebus.MixProject do
  use Mix.Project

  def project do
    [
      app: :pulsebus,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Pulsebus.CLI, path: "pulse", app: nil],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger],
      mod: {Pulsebus.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end
end
