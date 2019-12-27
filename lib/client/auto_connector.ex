defmodule  PN532.Client.AutoConnector do
  @behaviour :gen_statem
  require Logger

  def start_link(init_args) do
    :gen_statem.start(__MODULE__, init_args, [])
  end

  def child_spec(init_args) do
    %{id: __MODULE__, type: :worker, start: {__MODULE__, :start_link, [init_args]}}
  end

  def callback_mode, do: :handle_event_function

  def terminate(_reason, _state, _data), do: :ok

  @spec code_change(any, any, any, any) :: {:ok, any, any}
  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}

  def init(config) do
    handler = Map.get(config, :handler, PN532.DefaultHandler)

    Logger.info("#{inspect __MODULE__} Configuration: #{inspect config}")

    {:ok, :initialising, Map.put(config, :handler, handler), [{:next_event, :internal, :find_ports}]}
  end

  def handle_event(type, event, state, data) do
    Logger.info("State: #{inspect(type)}, #{inspect(event)}, #{inspect(state)}")

    apply(__MODULE__, state, [type, event, data])
  end

  def initialising(:internal, :find_ports, %{uart_port: uart_port} = data) do
    Logger.info("#{inspect __MODULE__} About to open UART: #{inspect uart_port}")
    PN532.Client.Server.open(uart_port)

    {:next_state, :connected, data}
  end

  def initialising(:internal, :find_ports, data) do
    {:next_state, :connecting, data, {:next_event, :internal, :find_ports}}
  end

  def connecting(:state_timeout, :find_ports, _data) do
    {:keep_state_and_data, {:next_event, :internal, :find_ports}}
  end

  def connecting(:internal, :find_ports, _data) do
    available_ports = Map.to_list(Circuits.UART.enumerate())

    {:keep_state_and_data, {:next_event, :internal, {:connect, available_ports}}}
  end

  def connecting(:internal, {:connect, []}, _data) do
    {:keep_state_and_data, {:state_timeout, 5000, :find_ports}}
  end

  def connecting(:internal, {:connect, [{first_port, _} | rest]}, data) do
    with {:open_port, :ok} <- {:open_port, PN532.Client.Server.open(first_port)},
         {:get_firmware, {:ok, version}} when is_map(version) <- {:get_firmware, PN532.Client.Server.get_firmware_version()} do

      connected_info = %{
        port: first_port,
        firmware_version: version
      }
      {:next_state, :connected, data, {:next_event, :internal, {:notify_handler, connected_info}}}
    else
      {:open_port, error} ->
        Logger.error("Failed to connect to port #{inspect first_port}, error: #{inspect error}, trying next port")
        {:keep_state_and_data, {:next_event, :internal, {:connect, rest}}}
      {:get_firmware, error} ->
        Logger.error("Failed to get firmware on port #{inspect first_port}, error: #{inspect error}, trying next port")
        {:keep_state_and_data, {:next_event, :internal, {:connect, rest}}}
    end
  end

  def connected(:internal, {:notify_handler, connected_info}, %{handler: handler}) do
    apply(handler, :connected, [connected_info])
    :keep_state_and_data
  end

end
