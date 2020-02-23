defmodule PN532.Client.Desfire do
  def get_version(device_id) do
    with {:ok, get_version} <- PN532.Client.send_desfire_command(device_id, 0x90, 0x60, 0x0, 0x0, 0x0) do
      PN532.Connection.Desfire.parse_get_version(get_version)
    else
      {:error, error} -> {:error, error}
      error -> {:error, error}
    end
  end
end
