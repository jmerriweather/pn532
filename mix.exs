defmodule Pn532.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/jmerriweather/pn532"
  @maintainers ["Jonathan Merriweather"]

  def project do
    [
      app: :pn532,
      version: @version,
      elixir: "~> 1.10",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "PN532",
      source_url: @url
    ]
  end

  defp package do
    [
      name: :pn532,
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{"GitHub" => @url},
      files: ["lib", "mix.exs", "README*", "LICENSE*"]
    ]
  end

  defp description do
    """
    Elixir library to work with the NXP PN532 RFID module.
    """
  end

  def docs do
    [
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      main: "readme"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_uart, "~> 1.4"},
      {:gen_state_machine, "~> 3.0"},
      {:earmark, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end
end
