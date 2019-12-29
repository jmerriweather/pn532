defmodule PN532.Client.Connecting do
  @moduledoc """
  Functions for when we are in the connecting state
  """
  require Logger

  @doc """
  if a uart port is defined
  """
  def connecting(:internal, :auto_connect, data = %{connection: connection, connection_options: connection_options}) do
    with {:ok, connected_info} <- connection.auto_connect(connection_options) do
      {:next_state, :connected, %{data | connection_options: %{connection_options | uart_open: true}}, [{:next_event, :internal, {:notify_handler, connected_info}}]}
    else
      error ->
        Logger.error("Error autoconnecting: #{inspect error}")
        {:keep_state_and_data, [{:state_timeout, 5000, :auto_connect}]}
    end
  end

  def connecting(:internal, {:auto_connect, from}, data = %{connection: connection, connection_options: connection_options}) do
    with {:ok, connected_info} <- connection.auto_connect(connection_options) do
      {:next_state, :connected, %{data | connection_options: %{connection_options | uart_open: true}}, [{:reply, from, {:ok, connected_info}}, {:next_event, :internal, {:notify_handler, connected_info}}]}
    else
      error ->
        Logger.error("Error autoconnecting: #{inspect error}")
        {:next_state, :disconnected, data, [{:reply, from, error}]}
    end
  end

  def connecting(:state_timeout, :auto_connect, _data) do
    {:keep_state_and_data, [{:next_event, :internal, :auto_connect}]}
  end
end
