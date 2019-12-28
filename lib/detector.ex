defmodule  PN532.Detector do
  @behaviour :gen_statem
  require Logger

  def start_link(init_args) do
    :gen_statem.start_link({:local, __MODULE__}, __MODULE__, init_args, [])
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

    Logger.debug("#{inspect __MODULE__} Configuration: #{inspect config}")

    {:ok, :waiting, Map.put(config, :handler, handler), [{:next_event, :internal, :wait_for_connection}]}
  end

  def start_detecting() do
    :gen_statem.cast(__MODULE__, :start_detecting)
  end

  def handle_event(type, event, state, data) do
    Logger.info("State: #{inspect(type)}, #{inspect(event)}, #{inspect(state)}")

    apply(__MODULE__, state, [type, event, data])
  end

  def waiting(:internal, :wait_for_connection, data) do
    if PN532.Client.AutoConnector.get_state() == :connected do
      {:next_state, :ready, data}
    else
      {:keep_state_and_data, {:state_timeout, 5000, :wait_for_connection}}
    end
  end

  def waiting(:state_timeout, :wait_for_connection, _data) do
    {:keep_state_and_data, {:next_event, :internal, :wait_for_connection}}
  end

  def ready(:cast, :start_detecting, data = %{handler: handler}) do
    case PN532.Client.in_auto_poll(255, 1, 0) do
      {:ok, 0} ->
        :ok
      {:ok, number, message} ->
        apply(handler, :handle_detection, [number, message])
        Logger.info("Detected card: #{inspect message}")
    end

    {:next_state, :detecting, data, [{:state_timeout, 1000, :detect}]}
  end

  def detecting(:state_timeout, :detect, _data) do


    {:keep_state_and_data, [{:state_timeout, 1000, :detect}]}
  end

end
