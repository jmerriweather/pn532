defmodule PN532.Client.Server do
  use GenServer
  require Logger
  require PN532.Client.Frames
  import PN532.Client.Frames

  @wakeup_preamble <<0x55, 0x55, 0x00, 0x00, 0x00>>
  @sam_mode_normal <<0x14, 0x01, 0x00, 0x00>>
  @ack_frame <<0x00, 0xFF>>
  @nack_frame <<0xFF, 0x00>>

  def open(com_port, uart_speed \\ nil) do
    GenServer.call(__MODULE__, {:open, com_port, uart_speed})
  end

  def close() do
    GenServer.call(__MODULE__, :close)
  end

  @spec get_current_card() :: {:ok, map} | {:error, term}
  def get_current_card() do
    GenServer.call(__MODULE__, :get_current_card)
  end

  def start_target_detection() do
    GenServer.cast(__MODULE__, :start_target_detection)
  end

  def stop_target_detection() do
    GenServer.cast(__MODULE__, :stop_target_detection)
  end

  def authenticate(device_id, block, key_type, key, card_id) do
    command =
      case key_type do
        :key_a -> 0x60
        :key_b -> 0x61
      end
    data = <<block>> <> key <> card_id

    GenServer.call(__MODULE__, {:in_data_exchange, device_id, command, data})
  end

  def read(device_id, block) do
    GenServer.call(__MODULE__, {:in_data_exchange, device_id, 0x30, <<block>>})
  end

  def write16(device_id, block, <<data::binary-size(16)>>) do
    GenServer.call(__MODULE__, {:in_data_exchange, device_id, 0xA0, <<block>> <> data})
  end

  def write4(device_id, block, <<data::binary-size(4)>>) do
    GenServer.call(__MODULE__, {:in_data_exchange, device_id, 0xA2, <<block>> <> data})
  end

  def in_data_exchange(device_id, cmd, addr, data) do
    GenServer.call(__MODULE__, {:in_data_exchange, device_id, cmd, <<addr, data>>})
  end

  def in_data_exchange(device_id, cmd, data) do
    GenServer.call(__MODULE__, {:in_data_exchange, device_id, cmd, data})
  end

  def in_auto_poll(poll_number, period, type) do
    GenServer.cast(__MODULE__, {:in_auto_poll, poll_number, period, type})
  end

  def get_firmware_version() do
    GenServer.call(__MODULE__, :get_firmware_version)
  end

  def get_general_status() do
    GenServer.call(__MODULE__, :get_general_status)
  end

  def in_list_passive_target(max_targets) do
    GenServer.call(__MODULE__, {:in_list_passive_target, max_targets})
  end

  def set_serial_baud_rate(baud_rate) do
    GenServer.call(__MODULE__, {:set_serial_baud_rate, baud_rate})
  end

  def get_target_type(target) do
    case target do
      :iso_14443_type_a -> {:ok, 0x00}
      :felica_212 -> {:ok, 0x01}
      :felica_424 -> {:ok, 0x02}
      :iso_14443_type_b -> {:ok, 0x03}
      :jewel -> {:ok, 0x04}
      _ -> {:error, :invalid_target_type}
    end
  end

  def get_baud_rate(baudrate) do
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

  # GenServer

  def child_spec(args) do
    %{id: __MODULE__, type: :worker, start: {__MODULE__, :start_link, [args]}}
  end

  # API
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(init_arg) do
    handler = Map.get(init_arg, :handler, PN532.DefaultHandler)
    target_type = Map.get(init_arg, :target_type, :iso_14443_type_a)
    uart_speed = Map.get(init_arg, :uart_speed, 115200)
    read_timeout = Map.get(init_arg, :read_timeout, 1500)
    detection_interval = Map.get(init_arg, :detection_interval, 50)
    {:ok,
      %{
          uart_pid: PN532.UART,
          uart_open: false,
          uart_speed: uart_speed,
          power_mode: :low_v_bat,
          handler: handler,
          target_type: target_type,
          current_cards: nil,
          detection_ref: nil,
          polling: false,
          poll_number: nil,
          poll_period: nil,
          poll_type: nil,
          read_timeout: read_timeout,
          detection_interval: detection_interval
      },
      {:continue, :setup}
    }
  end

  defp write_bytes(pid, bytes), do: Circuits.UART.write(pid, bytes)

  defp wakeup(%{uart_pid: uart_pid, power_mode: :low_v_bat}) do
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

  defp wakeup(%{power_mode: power_mode}) do
    power_mode
  end

  defp detect_card(uart_pid, target_type, max_targets, read_timeout, handler) do
    in_list_passive_target_command = <<0x4A, max_targets, target_type>>
    write_bytes(uart_pid, in_list_passive_target_command)

    receive do
      {:circuits_uart, _com_port, <<0xD5, 0x4B, total_cards::signed-integer, rest::binary>>} ->
        apply(handler, :handle_detection, [total_cards, rest])
    after
      read_timeout ->
        write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
        {:error, :timeout}
    end
  end

  def handle_continue(:setup, state = %{handler: handler}) do
    apply(handler, :setup, [state])

    {:noreply, state}
  end

  def handle_call(:get_current_card, _, state = %{current_cards: card}) do
    {:reply, {:ok, card}, state}
  end

  def handle_call({:open, _com_port, _uart_speed}, _, state = %{uart_open: true}) do
    {:reply, {:error, :already_open}, state}
  end

  def handle_call({:open, com_port, nil}, _from, state = %{uart_pid: uart_pid, uart_speed: uart_speed}) do
    with :ok <- Circuits.UART.open(uart_pid, com_port, speed: uart_speed, active: true, framing: PN532.Client.Framing) do
      {:reply, :ok, %{state | uart_open: true}}
    else
      error ->
        Logger.error("Error occured opening UART: #{inspect error}")
        {:reply, error, %{state | uart_speed: uart_speed}}
    end
  end

  def handle_call({:open, com_port, uart_speed}, _from, state = %{uart_pid: uart_pid}) do
    with :ok <- Circuits.UART.open(uart_pid, com_port, speed: uart_speed, active: true, framing: PN532.Client.Framing) do
      {:reply, :ok, %{state | uart_open: true}}
    else
      error ->
        Logger.error("Error occured opening UART: #{inspect error}")
        {:reply, error, %{state | uart_speed: uart_speed}}
    end
  end

  def handle_call(_, _, state = %{uart_open: false}) do
    {:reply, {:error, :not_open}, state}
  end

  def handle_call(:close, _from, state = %{uart_pid: uart_pid}) do
    response = Circuits.UART.close(uart_pid)
    {:reply, response, %{state | uart_open: false}}
  end

  def handle_call(:get_firmware_version, _from, state = %{uart_pid: uart_pid, read_timeout: read_timeout}) do
    new_power_mode = wakeup(state)

    firmware_version_command = <<0x02>>
    write_bytes(uart_pid, firmware_version_command)
    response =
      receive do
        {:circuits_uart, com_port, firmware_version_response(ic_version, version, revision, support)} ->
          Logger.debug("Received firmware version frame on #{inspect com_port} with version: #{inspect version}.#{inspect revision}.#{inspect support}")
          {:ok, %{ic_version: ic_version, version: version, revision: revision, support: support}}
      after
        read_timeout ->
          {:error, :timeout}
      end

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call(:get_general_status, _from, state = %{uart_pid: uart_pid, read_timeout: read_timeout}) do
    new_power_mode = wakeup(state)

    get_general_status_command = <<0x04>>
    write_bytes(uart_pid, get_general_status_command)
    response =
      receive do
        {:circuits_uart, com_port, <<0xD5, 0x05, message::bitstring>>} ->
          Logger.debug("Received general status frame on #{inspect com_port} with message: ")

          response = parse_general_status(message)

          {:ok, response}
      after
        read_timeout ->
          {:error, :timeout}
      end

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:set_serial_baud_rate, baud_rate}, _from, state = %{uart_pid: uart_pid, read_timeout: read_timeout}) do
    new_power_mode = wakeup(state)

    response =
      # convert baud rate number into baud rate command byte
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

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:in_data_exchange, device_id, cmd, data}, _from, state = %{uart_pid: uart_pid, read_timeout: read_timeout}) do
    new_power_mode = wakeup(state)

    write_bytes(uart_pid, <<0x40>> <> <<device_id>> <> <<cmd>> <> data)
    response =
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

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:in_list_passive_target, max_targets}, _from, state = %{uart_pid: uart_pid, target_type: target_type, read_timeout: read_timeout, handler: handler}) do

    with {:ok, target_byte} <- get_target_type(target_type) do
      new_power_mode = wakeup(state)
      response = detect_card(uart_pid, target_byte, max_targets, read_timeout, handler)

      {:reply, response, %{state | power_mode: new_power_mode}}
    else
      error -> error
    end
  end

  def handle_cast({:in_auto_poll, poll_number, period, type}, state = %{uart_pid: uart_pid}) do
    new_power_mode = wakeup(state)

    in_auto_poll_command = in_auto_poll_request_frame(poll_number, period, type)
    write_bytes(uart_pid, in_auto_poll_command)

    {:noreply, %{state | power_mode: new_power_mode, polling: true, poll_number: poll_number, poll_period: period, poll_type: type}}
  end

  # def handle_cast(:in_jump_for_dep, state = %{uart_pid: uart_pid}) do
  #   new_power_mode = wakeup(state)

  #   in_jump_for_dep_command = in_auto_poll_request_frame(poll_number, period, type)
  #   write_bytes(uart_pid, in_jump_for_dep_command)

  #   {:noreply, %{state | power_mode: new_power_mode}}
  # end

  def handle_cast(:stop_target_detection, state = %{uart_pid: uart_pid, polling: true}) do
    # send ACK frame to cancel last command
    write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
    {:noreply, %{state | polling: false, poll_number: nil, poll_period: nil, poll_type: nil}}
  end

  def handle_cast(:stop_target_detection, state = %{detection_ref: nil}) do
    Logger.error("Target detection has not been started")
    {:noreply, state}
  end

  def handle_cast(:stop_target_detection, state = %{uart_pid: uart_pid, detection_ref: detection_ref}) when detection_ref != nil do
    Process.cancel_timer(detection_ref)
    # send ACK frame to cancel last command
    write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
    {:noreply, %{state | detection_ref: nil, current_cards: nil}}
  end

  def handle_cast(:start_target_detection, state = %{detection_ref: detection_ref}) when detection_ref != nil do
    Logger.error("Target detection has already been started")
    {:noreply, state}
  end

  def handle_cast(:start_target_detection, state = %{polling: true}) do
    Logger.error("Target detection has already been started")
    {:noreply, state}
  end

  def handle_cast(:start_target_detection, state) do
    Logger.debug("Starting target detection")

    in_auto_poll(255, 1, 0)

    {:noreply, state}
  end

  def handle_info(:detect_target, state = %{uart_pid: uart_pid, target_type: target_type, current_cards: current_cards, detection_interval: detection_interval, read_timeout: read_timeout, handler: handler}) do
    new_power_mode = wakeup(state)

    new_state =
      with {:ok, target_byte} <- get_target_type(target_type),
           {:ok, card} <- detect_card(uart_pid, target_byte, 1, read_timeout, handler) do
        if current_cards != card do
          apply(handler, :handle_event, [:cards_detected, card])
        end
        %{state | current_cards: card}
      else
        _ ->
          if current_cards != nil do
            apply(handler, :handle_event, [:cards_lost, current_cards])
          end
          %{state | current_cards: nil}
      end

    detection_ref = Process.send_after(self(), :detect_target, detection_interval)

    {:noreply, %{new_state | power_mode: new_power_mode, detection_ref: detection_ref}}
  end

  def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 0, _rest::bitstring>>},
    state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with no cards")

    if polling do
      if current_cards != nil do
        apply(handler, :handle_event, [:cards_lost, current_cards])
      end

      handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
    else
      {:noreply, %{state | current_cards: nil}}
    end
  end

  def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 1, in_auto_poll_response(_type, message), _padding::bitstring>>},
    state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with message: #{inspect message}")

    detected = apply(handler, :handle_detection, [1, [message]])

    if polling do
      with {:ok, cards} <- detected do
        if current_cards !== cards do
          apply(handler, :handle_event, [:cards_detected, cards])
        end
        handle_cast({:in_auto_poll, 7, period, type}, %{state | current_cards: cards})
      else
        _ ->
          handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 2, in_auto_poll_response(_type1, message1), in_auto_poll_response(_type2, message2), _padding::bitstring>>},
    state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
    Logger.debug("Received in_auto_poll frame on #{inspect com_port} with two cards with message: #{inspect message1} and #{inspect message2}")

    detected = apply(handler, :handle_detection, [2, [message1, message2]])

    if polling do
      with {:ok, cards} <- detected do
        if current_cards !== cards do
          apply(handler, :handle_event, [:cards_detected, cards])
        end
        handle_cast({:in_auto_poll, 7, period, type}, %{state | current_cards: cards})
      else
        _ ->
          handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:circuits_uart, com_port, <<0x7F>>}, state) do
    Logger.error("Received Error frame on #{inspect com_port}")
    {:noreply, state}
  end

  def handle_info({:circuits_uart, com_port, @ack_frame}, state) do
    Logger.debug("Received ACK frame on #{inspect com_port}")
    {:noreply, state}
  end

  def handle_info({:circuits_uart, com_port, @nack_frame}, state) do
    Logger.debug("Received NACK frame on #{inspect com_port}")
    {:noreply, state}
  end
end
