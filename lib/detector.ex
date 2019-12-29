defmodule  PN532.Detector do
  use GenStateMachine
  require Logger

  def start_link(init_args) do
    GenStateMachine.start_link(__MODULE__, init_args, [name: __MODULE__])
  end

  def child_spec(init_args) do
    %{id: __MODULE__, type: :worker, start: {__MODULE__, :start_link, [init_args]}}
  end

  def init(init_arg) do
    Logger.debug("#{inspect __MODULE__} Configuration: #{inspect init_arg}")

    handler = Map.get(init_arg, :handler, PN532.DefaultHandler)

    data = %{
      handler: handler,
      current_cards: []
    }

    {:ok, :waiting, data, [{:next_event, :internal, :wait_for_connection}]}
  end

  def start_detecting() do
    GenStateMachine.cast(__MODULE__, :start_detecting)
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
    cards = poll_cards(2, data)

    {:next_state, :detecting, data, [{:next_event, :internal, {:check_cards, cards}}]}
  end

  def detecting(:state_timeout, :detect, data) do
    cards = poll_cards(2, data)

    {:keep_state, data, [{:next_event, :internal, {:check_cards, cards}}]}
  end

  def detecting(:internal, {:check_cards, cards = []}, data = %{current_cards: current_cards, handler: handler}) do
    if cards !== current_cards do
      apply(handler, :handle_event, [:cards_lost, current_cards])
    end

    {:keep_state, %{data | current_cards: cards}, [{:state_timeout, 1000, :detect}]}
  end

  def detecting(:internal, {:check_cards, cards}, data = %{current_cards: current_cards, handler: handler}) do
    if cards !== current_cards do
      apply(handler, :handle_event, [:cards_detected, cards])
    end

    {:keep_state, %{data | current_cards: cards}, [{:state_timeout, 1000, :detect}]}
  end

  def poll_cards(max_targets, %{handler: handler}) do

    case PN532.Client.in_list_passive_target(max_targets) do
      {:ok, 0} ->
        []
      {:ok, [number, message]} ->
        with {:ok, cards} <- apply(handler, :handle_detection, [number, message]) do
          cards
        else
          _ -> []
        end
      {:error, :timeout} -> []
    end
  end

end
