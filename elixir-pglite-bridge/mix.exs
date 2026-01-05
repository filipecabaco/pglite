defmodule PgliteEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :pglite_ex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir bridge to PGlite WASM - PostgreSQL in WebAssembly",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PgliteEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wasmex, "~> 0.9.2"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "pglite_ex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/electric-sql/pglite",
        "PGlite" => "https://pglite.dev"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
