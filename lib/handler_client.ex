defmodule PN532.HandlerClient do
  alias __MODULE__

  defstruct [:connection, :connection_options, :detected_cards]

  def new(connection, connection_options) do
    %HandlerClient{connection: connection, connection_options: connection_options}
  end

  def wakeup(data) do
    data.connection.wakeup(data)
  end

  def authenticate(client, device_id, block, key_type, key, card_id) do
    command =
      case key_type do
        :key_a -> 0x60
        :key_b -> 0x61
      end
    data = <<block>> <> key <> card_id

    client.connection.in_data_exchange(client.connection_options, device_id, command, data)
  end

  def read(client, device_id, block) do
    client.connection.in_data_exchange(client.connection_options, device_id, 0x30, <<block>>)
  end

  def select(client, device_id) do
    client.connection.in_select(client.connection_options, device_id)
  end

  def deselect(client, device_id) do
    client.connection.in_deselect(client.connection_options, device_id)
  end
end
