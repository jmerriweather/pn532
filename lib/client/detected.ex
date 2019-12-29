defmodule PN532.Client.Detected do
  @moduledoc """
  Functions for when we are in the connected state
  """
  require Logger

  def detected(:internal, {:cards_detected, cards},
    data = %{current_cards: current_cards, handler: handler, connection: connection, connection_options: connection_options}) do

    handler_response =
      if current_cards !== cards do
        apply(handler, :handle_event, [:cards_detected, cards, PN532.HandlerClient, PN532.HandlerClient.new(connection, connection_options)])
      end

    case handler_response do
      {:noreply, %{connection: new_connection, connection_options: connection_options, detected_cards: detected_cards}} ->
        {:next_state, :detecting, %{data | current_cards: cards, connection: new_connection, connection_options: connection_options, detected_cards: detected_cards}, [{:state_timeout, 1000, :poll_for_cards}]}
      {:noreply, %{connection: new_connection, connection_options: connection_options}} ->
        {:next_state, :detecting, %{data | current_cards: cards, connection: new_connection, connection_options: connection_options}, [{:state_timeout, 1000, :poll_for_cards}]}
      _ ->
        {:next_state, :detecting, data, [{:state_timeout, 1000, :poll_for_cards}]}
    end
  end

  # def detected(:state_timeout, :poll_status, _data) do
  #   {:keep_state_and_data, [{:next_event, :internal, :poll_status}]}
  # end

  # def detected(:internal, :poll_status, data = %{connection: connection, connection_options: connection_options, current_targets: current_targets}) do
  #   with {:ok, %{targets: targets}} <- connection.get_general_status(connection_options) do
  #     Logger.info("Targets: #{inspect targets}, current targets: #{inspect current_targets}")
  #     if current_targets !== targets do
  #       {:next_state, :detecting, data, [{:next_event, :internal, :poll_for_cards}]}
  #     else
  #       {:keep_state_and_data, [{:state_timeout, 1000, :poll_status}]}
  #     end
  #   else
  #     _ -> :keep_state_and_data
  #   end
  # end

  def detected(type, event, data) do
    case PN532.Client.Connected.connected(type, event, data) do
      {option, data, actions} when is_list(actions) ->
        {option, data, actions ++ [{:state_timeout, 100, :poll_for_cards}]}
      {option, actions} when is_list(actions) ->
        {option, actions ++ [{:state_timeout, 100, :poll_for_cards}]}
    end
  end
end
