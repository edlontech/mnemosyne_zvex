defmodule MnemosyneZvex.MixProject do
  use Mix.Project

  def project do
    [
      app: :mnemosyne_zvex,
      version: "0.1.0",
      elixir: "~> 1.19",
      test_coverage: [tool: ExCoveralls],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MnemosyneZvex.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.post": :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "test.integration": :test
      ]
    ]
  end

  defp aliases do
    [
      "test.integration": ["test --only integration"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.8", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: :dev},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:assert_eventually, "~> 1.0", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mnemosyne, "~> 0.1"},
      {:recode, "~> 0.8", only: [:dev], runtime: false},
      {:splode, "~> 0.3"},
      {:telemetry, "~> 1.3"},
      {:tidewave, "~> 0.5", only: :dev, runtime: false},
      {:zvex, github: "edlontech/zvex", branch: "main"}
    ]
  end
end
