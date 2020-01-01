defmodule PN532.Client.Detecting do
  @moduledoc """
  Functions for when we are in the connected state
  """
  require Logger
  require PN532.Connection.Frames
  import PN532.Connection.Frames

  def detecting(:cast, :stop_target_detection, data)  do
    {:next_state, :connected, data}
  end

  def detecting(:internal, :poll_for_cards, data = %{connection: connection, connection_options: connection_options, poll_number: poll_number, poll_period: period, poll_type: type}) do
    new_power_mode = connection.wakeup(data)
    connection.in_auto_poll(connection_options, poll_number, period, type)
    {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}}
  end

  def detecting(:state_timeout, :poll_for_cards, _data) do
    {:keep_state_and_data, [{:next_event, :internal, :poll_for_cards}]}
    #:keep_state_and_data
  end

  def detecting(:info, {:circuits_uart, com_port, <<0xD5, 0x61, 0, _rest::bitstring>>}, data = %{current_cards: current_cards, handler: handler, connection: connection, connection_options: connection_options}) do
    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with no cards")

    {:noreply, client} =
      if current_cards != nil do
        apply(handler, :handle_event, [:cards_lost, current_cards, PN532.HandlerClient, PN532.HandlerClient.new(connection, connection_options)])
      end

    {:keep_state, %{data | current_cards: nil, poll_number: 255, connection: client.connection, connection_options: client.connection_options}, [{:state_timeout, 100, :poll_for_cards}]}
  end

  def detecting(:info, {:circuits_uart, com_port, <<0xD5, 0x61, 1, in_auto_poll_response(_type, message), _padding::bitstring>>},
                data = %{handler: handler}) do
    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with message: #{inspect message}")

    detected = apply(handler, :handle_detection, [1, [message]])

    with {:ok, cards} <- detected do
      {:next_state, :detected, %{data | poll_number: 7}, [{:next_event, :internal, {:cards_detected, cards}}]}
    else
      _ ->
        {:keep_state, %{data | current_cards: nil, poll_number: 255}, [{:state_timeout, 100, :poll_for_cards}]}
    end
  end

  def detecting(:info, {:circuits_uart, com_port, <<0xD5, 0x61, 2, in_auto_poll_response(_type1, message1), in_auto_poll_response(_type2, message2), _padding::bitstring>>},
    data = %{handler: handler}) do

    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with two cards with message: #{inspect message1} and #{inspect message2}")

    detected = apply(handler, :handle_detection, [2, [message1, message2]])

    with {:ok, cards} <- detected do
      {:next_state, :detected, %{data | poll_number: 7}, [{:next_event, :internal, {:cards_detected, cards}}]}
    else
      _ ->
        {:keep_state, %{data | current_cards: nil, poll_number: 255}, [{:state_timeout, 100, :poll_for_cards}]}
    end
  end

  def detecting(type, event, data) do
    case PN532.Client.Connected.connected(type, event, data) do
      {option, data, actions} when is_list(actions) ->
        {option, data, actions ++ [{:state_timeout, 100, :poll_for_cards}]}
      {option, actions} when is_list(actions) ->
        {option, actions ++ [{:state_timeout, 100, :poll_for_cards}]}
    end
  end
end
