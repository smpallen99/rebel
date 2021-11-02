defmodule Rebel.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rebel,
      version: "0.3.2",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :eex], mod: {Rebel.Application, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:poison, "~> 4.0", override: true},
      {:cowboy, "~> 2.7", only: :test},
      {:ex_doc, "~> 0.24", only: :dev},
      {:jason, "~> 1.2"}
    ]
  end
end
