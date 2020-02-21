defmodule PN532.Supervisor do
  @moduledoc """
  Documentation for PN532.
  """
  use Supervisor

  def start_link([_config, opts] = args) do
    Supervisor.start_link(__MODULE__, args, opts)
  end

  def start_link([config]) do
    start_link([config, []])
  end

  @doc false
  @impl Supervisor
  def init([config, opts]) do
    opts = Keyword.put(opts, :strategy, :one_for_all)
    target_type = Map.get(config, :target_type, :iso_14443_type_a)
    children = get_configured_client(Map.put(config, :target_type, target_type))
    Supervisor.init(children, opts)
  end

  def get_configured_client(%{target_type: :iso_14443_type_a} = config) do
    [
      %{
        id: PN532.UART,
        start: {Circuits.UART, :start_link, [[name: PN532.UART]]}
      },
      %{
        id: config.target_type,
        start: {PN532.Client, :start_link, [config]}
      }
    ]
  end

  def get_configured_client(config) do
    [
      %{
        id: PN532.UART,
        start: {Circuits.UART, :start_link, [[name: PN532.UART]]}
      },
      %{
        id: config.target_type,
        start: {PN532.Client, :start_link, [config]}
      }
    ]
  end
end
