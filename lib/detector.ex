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

    data = config
    |> Map.put(:handler, handler)
    |> Map.put(:current_cards, [])

    {:ok, :waiting, data, [{:next_event, :internal, :wait_for_connection}]}
  end

  def start_detecting() do
    :gen_statem.cast(__MODULE__, :start_detecting)
  end

  def handle_event(type, event, state, data) do
    Logger.info("#{inspect __MODULE__} State: #{inspect(type)}, #{inspect(event)}, #{inspect(state)}")

    apply(__MODULE__, state, [type, event, data])
  end

  def waiting(:internal, :wait_for_connection, data) do
    if PN532.Client.AutoConnector.get_state() == :connected do
      Logger.info("#{inspect __MODULE__} WE ARE READY...")
      {:next_state, :ready, data}
    else
      {:keep_state_and_data, [{:state_timeout, 500, :wait_for_connection}]}
    end
  end

  def waiting(:state_timeout, :wait_for_connection, _data) do
    Logger.info("Waiting for connection...")
    {:keep_state_and_data, [{:next_event, :internal, :wait_for_connection}]}
  end

  def ready(:cast, :start_detecting, data) do
    cards = poll_cards(255, 1, 0, data)

    {:next_state, :detecting, data, [{:next_event, :internal, {:check_cards, cards}}]}
  end

  def detecting(:state_timeout, :detect, data) do
    cards = poll_cards(255, 1, 0, data)

    {:keep_state, data, [{:next_event, :internal, {:check_cards, cards}}]}
  end

  def detection(:internal, {:check_cards, cards = []}, data = %{current_cards: current_cards, handler: handler}) do
    if cards !== current_cards do
      apply(handler, :handle_event, [:cards_lost, current_cards])
    end

    {:keep_state, %{data | current_cards: cards}, [{:state_timeout, 1000, :detect}]}
  end

  def detection(:internal, {:check_cards, cards}, data = %{current_cards: current_cards, handler: handler}) do
    if cards !== current_cards do
      apply(handler, :handle_event, [:cards_detected, cards])
    end

    {:keep_state, %{data | current_cards: cards}, [{:state_timeout, 1000, :detect}]}
  end

  def poll_cards(poll_number, period, type, %{handler: handler}) do
    case PN532.Client.in_auto_poll(poll_number, period, type) do
      {:ok, 0} ->
        []
      {:ok, number, message} ->
        with {:ok, cards} <- apply(handler, :handle_detection, [number, message]) do
          cards
        else
          _ -> []
        end
    end
  end

end
