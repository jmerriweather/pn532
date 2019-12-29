defmodule PN532.Connection.Uart do
  require Logger
  require PN532.Connection.Frames
  import PN532.Connection.Frames

  @wakeup_preamble <<0x55, 0x55, 0x00, 0x00, 0x00>>
  @sam_mode_normal <<0x14, 0x01, 0x00, 0x00>>
  @ack_frame <<0x00, 0xFF>>

  defp write_bytes(pid, bytes), do: Circuits.UART.write(pid, bytes)

  defp get_baud_rate(baudrate) do
    case baudrate do
      9_600 -> {:ok, <<0x00>>}
      19_200 -> {:ok, <<0x01>>}
      38_400 -> {:ok, <<0x02>>}
      57_600 -> {:ok, <<0x03>>}
      115_200 -> {:ok, <<0x04>>}
      230_400 -> {:ok, <<0x05>>}
      460_800 -> {:ok, <<0x06>>}
      921_600 -> {:ok, <<0x07>>}
      1_288_000 -> {:ok, <<0x08>>}
      _ -> :invalid_baud_rate
    end
  end

  def auto_connect(connect_options = %{uart_port: uart_port}) when not is_nil(uart_port) do
    auto_connect(connect_options, [{uart_port, ""}])
  end

  def auto_connect(connect_options) do
    available_ports = Map.to_list(Circuits.UART.enumerate())
    auto_connect(connect_options, available_ports)
  end

  def auto_connect(connect_options, [{first_port, _} | rest]) do
    with {:open_port, :ok} <- {:open_port, open(connect_options, first_port)},
         {:wakeup, :normal} <- {:wakeup, wakeup(%{connection_options: connect_options})},
         {:get_firmware, {:ok, version}} when is_map(version) <- {:get_firmware, get_firmware_version(connect_options)} do

      connected_info = %{
        port: first_port,
        firmware_version: version
      }
      {:ok, connected_info}
    else
      {:open_port, error} ->
        Logger.error("Failed to connect to port #{inspect first_port}, error: #{inspect error}, trying next port")
        auto_connect(connect_options, rest)
      {:wakeup, error} ->
        Logger.error("Failed to wakeup #{inspect first_port}, error: #{inspect error}, trying next port")
        auto_connect(connect_options, rest)
      {:get_firmware, error} ->
        Logger.error("Failed to get firmware on port #{inspect first_port}, error: #{inspect error}, trying next port")
        auto_connect(connect_options, rest)
    end
  end
  def auto_connect(_, []) do
    {:error, :no_ports_avaialble}
  end

  def open(%{uart_pid: uart_pid, uart_speed: uart_speed, uart_port: uart_port}, _) when not is_nil(uart_port) do
    Circuits.UART.open(uart_pid, uart_port, speed: uart_speed, active: true, framing: PN532.Connection.Uart.Framing)
  end

  def open(%{uart_pid: uart_pid, uart_speed: uart_speed}, uart_port) do
    Circuits.UART.open(uart_pid, uart_port, speed: uart_speed, active: true, framing: PN532.Connection.Uart.Framing)
  end

  def open(%{uart_pid: uart_pid}, uart_port, uart_speed) do
    Circuits.UART.open(uart_pid, uart_port, speed: uart_speed, active: true, framing: PN532.Connection.Uart.Framing)
  end

  def close(%{uart_pid: uart_pid}) do
    Circuits.UART.close(uart_pid)
  end

  def wakeup(%{connection_options: %{uart_pid: uart_pid, power_mode: :low_v_bat}}) do
    Circuits.UART.write(uart_pid, @wakeup_preamble)
    Circuits.UART.write(uart_pid, @sam_mode_normal)
    receive do
      ack -> Logger.debug("SAM ACK: #{inspect ack}")
    after
      16 -> :timeout
    end

    receive do
      response -> Logger.debug("SAM response: #{inspect response}")
    after
      16 -> :timeout
    end

    :normal
  end

  def wakeup(%{connection_options: %{power_mode: power_mode}}) do
    power_mode
  end

  def get_firmware_version(%{uart_pid: uart_pid, read_timeout: read_timeout}) do
    firmware_version_command = <<0x02>>
    write_bytes(uart_pid, firmware_version_command)

    receive do
      {:circuits_uart, com_port, firmware_version_response(ic_version, version, revision, support)} ->
        Logger.debug("Received firmware version frame on #{inspect com_port} with version: #{inspect version}.#{inspect revision}.#{inspect support}")
        {:ok, %{ic_version: ic_version, version: version, revision: revision, support: support}}
    after
      read_timeout ->
        {:error, :timeout}
    end
  end

  def get_general_status(%{uart_pid: uart_pid, read_timeout: read_timeout}) do
    get_general_status_command = <<0x04>>
    write_bytes(uart_pid, get_general_status_command)

    receive do
      {:circuits_uart, com_port, <<0xD5, 0x05, message::bitstring>>} ->
        Logger.debug("Received general status frame on #{inspect com_port} with message: ")

        response = parse_general_status(message)

        {:ok, response}
    after
      read_timeout ->
        {:error, :timeout}
    end
  end

  def set_serial_baud_rate(%{uart_pid: uart_pid, read_timeout: read_timeout}, baud_rate) do
    with {:ok, baudrate_byte} <- get_baud_rate(baud_rate) do
      command = <<0x10>> <> baudrate_byte
      # send set baud rate command
      write_bytes(uart_pid, command)

      receive do
        # wait for ACK message
        {:circuits_uart, _com_port, @ack_frame} ->
          receive do
            # wait for success message
            {:circuits_uart, _com_port, <<0xD5, 0x11>>} ->
              # send ACK frame to let the PN532 know we are ready to change
              write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
              # sleep for 20ms
              Process.sleep(20)
              # change baud rate of UART
              with :ok <- Circuits.UART.configure(uart_pid, speed: baud_rate) do
                {:ok, baud_rate}
              else
                error -> error
              end
            {:circuits_uart, _com_port, <<0xD5, 0x11, status>>} ->
              error = get_error(status)
              {:error, error}
          after
            read_timeout ->
              {:error, :timeout}
          end
      after
        read_timeout * 2 ->
          {:error, :timeout}
      end
    else
      error -> {:error, error}
    end
  end

  def in_select(%{uart_pid: uart_pid, read_timeout: read_timeout}, device_id) do
    write_bytes(uart_pid, <<0x54>> <> <<device_id>>)

    receive do
      {:circuits_uart, _com_port, <<0xD5, 0x55, 0>>} ->
        :ok
      {:circuits_uart, _com_port, <<0xD5, 0x55, status>>} ->
        error =  get_error(status)
        {:error, error}
    after
      read_timeout ->
        {:error, :timeout}
    end
  end

  def in_deselect(%{uart_pid: uart_pid, read_timeout: read_timeout}, device_id) do
    write_bytes(uart_pid, <<0x44>> <> <<device_id>>)

    receive do
      {:circuits_uart, _com_port, <<0xD5, 0x45, 0>>} ->
        :ok
      {:circuits_uart, _com_port, <<0xD5, 0x45, status>>} ->
        error =  get_error(status)
        {:error, error}
    after
      read_timeout ->
        {:error, :timeout}
    end
  end

  def in_data_exchange(%{uart_pid: uart_pid, read_timeout: read_timeout}, device_id, cmd, data) do
    write_bytes(uart_pid, <<0x40>> <> <<device_id>> <> <<cmd>> <> data)

    receive do
      # Data exchange was successful, this is returned on successful authentication
      {:circuits_uart, _com_port, <<0xD5, 0x41, 0>>} -> :ok
      # Data exchange was successful, with resulting data
      {:circuits_uart, _com_port, <<0xD5, 0x41, 0, rest::binary>>} -> {:ok, rest}
      # Error happened
      {:circuits_uart, _com_port, <<0xD5, 0x41, status>>} ->
        error =  get_error(status)
        {:error, error}
    after
      read_timeout ->
        {:error, :timeout}
    end
  end

  def in_list_passive_target(%{uart_pid: uart_pid, read_timeout: read_timeout}, target_type, max_targets) do
    in_list_passive_target_command = <<0x4A, max_targets, target_type>>
    write_bytes(uart_pid, in_list_passive_target_command)

    receive do
      {:circuits_uart, _com_port, <<0xD5, 0x4B, total_cards::signed-integer, rest::binary>>} ->
        {:ok, [total_cards, rest]}
    after
      read_timeout ->
        write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
        {:error, :timeout}
    end
  end

  def in_auto_poll(%{uart_pid: uart_pid}, poll_number, period, type) do
    in_auto_poll_command = in_auto_poll_request_frame(poll_number, period, type)
    write_bytes(uart_pid, in_auto_poll_command)
  end
end
