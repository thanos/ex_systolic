defmodule ExSystolic.MixProject do
  use Mix.Project

  @source_url "https://github.com/thanos/ex_systolic"
  @version "0.1.0"

  def project do
    [
      app: :ex_systolic,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "A BEAM-native systolic array simulator -- clocked spatial dataflow with explicit ticks, links, and processing elements.",
      package: package(),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        threshold: 90
      ],
      dialyzer: [
        plt_local_path: "priv/plts/local.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["Thanos Vassilakis"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Coveralls" => "https://coveralls.io/github/thanos/ex_systolic"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "README"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        Core: [
          ExSystolic.Grid,
          ExSystolic.Link,
          ExSystolic.PE,
          ExSystolic.Array,
          ExSystolic.Clock,
          ExSystolic.Trace
        ],
        Space: [
          ExSystolic.Space,
          ExSystolic.Space.Grid2D
        ],
        "Processing Elements": [ExSystolic.PE.MAC],
        Backends: [ExSystolic.Backend.Interpreted],
        Examples: [ExSystolic.Examples.GEMM]
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.2", only: [:test, :dev]},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end
end
