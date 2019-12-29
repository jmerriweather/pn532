defmodule PN532.Client.Connected do
  @moduledoc """
  Functions for when we are in the connected state
  """
  require Logger

  def connected(:internal, {:notify_handler, connected_info}, %{handler: handler}) do
    Logger.debug("#{inspect __MODULE__} About to Notify handler #{inspect handler} about #{inspect connected_info}")
    apply(handler, :connected, [connected_info])
    :keep_state_and_data
  end

  def connected(:cast, :start_target_detection, data) do
    {:next_state, :detecting, data, [{:next_event, :internal, :poll_for_cards}]}
  end

  def connected({:call, from}, :get_firmware_version, data = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(data)
    response = connection.get_firmware_version(connection_options)
    {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}, [{:reply, from, response}]}
  end

  def connected({:call, from}, :get_general_status, data = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(data)
    response = connection.get_general_status(connection_options)
    {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}, [{:reply, from, response}]}
  end

  def connected({:call, from}, {:set_serial_baud_rate, baud_rate}, data = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(data)
    response = connection.set_serial_baud_rate(connection_options, baud_rate)
    {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}, [{:reply, from, response}]}
  end

  def connected({:call, from}, {:in_data_exchange, device_id, cmd, message}, data = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(data)
    response = connection.in_data_exchange(connection_options, device_id, cmd, message)
    {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}, [{:reply, from, response}]}
  end

  def connected({:call, from}, {:in_list_passive_target, max_targets}, data = %{connection: connection, connection_options: connection_options, target_type: target_type}) do
    with {:ok, target_byte} <- PN532.Connection.Frames.get_target_type(target_type) do
      new_power_mode = connection.wakeup(data)
      response =connection.in_list_passive_target(connection_options, target_byte, max_targets)

      {:keep_state, %{data | connection_options: %{connection_options | power_mode: new_power_mode}}, [{:reply, from, response}]}
    else
      error ->
        {:keep_state_and_data, [{:reply, from, error}]}
    end
  end
end
