defmodule PN532.Client do
  use GenServer
  require Logger

  @ack_frame <<0x00, 0xFF>>
  @nack_frame <<0xFF, 0x00>>

  def open(com_port, uart_speed \\ nil) do
    GenServer.call(__MODULE__, {:open, com_port, uart_speed})
  end

  def close() do
    GenServer.call(__MODULE__, :close)
  end

  @spec get_current_cards() :: {:ok, map} | {:error, term}
  def get_current_cards() do
    GenServer.call(__MODULE__, :get_current_cards)
  end

  def start_target_detection() do
    #GenServer.cast(__MODULE__, :start_target_detection)
  end

  def stop_target_detection() do
    #GenServer.cast(__MODULE__, :stop_target_detection)
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
    GenServer.call(__MODULE__, {:in_auto_poll, poll_number, period, type})
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
    detection_interval = Map.get(init_arg, :detection_interval, 50)
    connection_options = Map.get(init_arg, :connection_options, %{})

    uart_pid = Map.get(connection_options, :uart_pid, PN532.UART)
    uart_speed = Map.get(connection_options, :uart_speed, 115200)
    read_timeout = Map.get(connection_options, :read_timeout, 1500)

    connection = Map.get(init_arg, :connection, PN532.Connection.Uart)
    {:ok,
      %{
          connection: connection,
          connection_options: %{
            uart_pid: uart_pid,
            uart_speed: uart_speed,
            uart_open: false,
            read_timeout: read_timeout
          },
          power_mode: :low_v_bat,
          handler: handler,
          target_type: target_type,
          current_cards: nil,
          detection_ref: nil,
          polling: false,
          poll_number: nil,
          poll_period: nil,
          poll_type: nil,
          detection_interval: detection_interval
      },
      {:continue, :setup}
    }
  end

  # defp write_bytes(pid, bytes), do: Circuits.UART.write(pid, bytes)

  # defp wakeup(%{uart_pid: uart_pid, power_mode: :low_v_bat}) do
  #   Circuits.UART.write(uart_pid, @wakeup_preamble)
  #   Circuits.UART.write(uart_pid, @sam_mode_normal)
  #   receive do
  #     ack -> Logger.debug("SAM ACK: #{inspect ack}")
  #   after
  #     16 -> :timeout
  #   end

  #   receive do
  #     response -> Logger.debug("SAM response: #{inspect response}")
  #   after
  #     16 -> :timeout
  #   end

  #   :normal
  # end

  # defp wakeup(%{power_mode: power_mode}) do
  #   power_mode
  # end

  # defp detect_card(uart_pid, target_type, max_targets, read_timeout, handler) do
  #   in_list_passive_target_command = <<0x4A, max_targets, target_type>>
  #   write_bytes(uart_pid, in_list_passive_target_command)

  #   receive do
  #     {:circuits_uart, _com_port, <<0xD5, 0x4B, total_cards::signed-integer, rest::binary>>} ->
  #       apply(handler, :handle_detection, [total_cards, rest])
  #   after
  #     read_timeout ->
  #       write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
  #       {:error, :timeout}
  #   end
  # end

  def handle_continue(:setup, state = %{handler: handler}) do
    apply(handler, :setup, [state])

    {:noreply, state}
  end

  def handle_call(:get_current_cards, _, state = %{current_cards: cards}) do
    {:reply, {:ok, cards}, state}
  end

  def handle_call({:open, _com_port, _uart_speed}, _, state = %{connection_options: %{uart_open: true}}) do
    {:reply, {:error, :already_open}, state}
  end

  def handle_call({:open, com_port, nil}, _from, state = %{connection: connection, connection_options: connection_options}) do
    with :ok <- connection.open(connection_options, com_port) do
      {:reply, :ok, %{state | connection_options: %{connection_options | uart_open: true}}}
    else
      error ->
        Logger.error("Error occured opening UART: #{inspect error}")
        {:reply, error, state}
    end
  end

  def handle_call({:open, com_port, uart_speed}, _from, state = %{connection: connection, connection_options: connection_options}) do
    with :ok <- connection.open(connection_options, com_port, uart_speed) do
      {:reply, :ok, %{state | connection_options: %{connection_options | uart_open: true, uart_speed: uart_speed}}}
    else
      error ->
        Logger.error("Error occured opening UART: #{inspect error}")
        {:reply, error, %{state | connection_options: %{connection_options | uart_speed: uart_speed}}}
    end
  end

  def handle_call(_, _, state = %{connection_options: %{uart_open: false}}) do
    {:reply, {:error, :not_open}, state}
  end

  def handle_call(:close, _from, state = %{connection: connection, connection_options: connection_options}) do
    response = connection.close(connection_options)
    {:reply, response, %{state | connection_options: %{connection_options | uart_open: false}}}
  end

  def handle_call(:get_firmware_version, _from, state = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(state)

    response = connection.get_firmware_version(connection_options)

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call(:get_general_status, _from, state = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(state)

    response = connection.get_general_status(connection_options)

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:set_serial_baud_rate, baud_rate}, _from, state = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(state)

    response = connection.set_serial_baud_rate(connection_options, baud_rate)

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:in_data_exchange, device_id, cmd, data}, _from, state = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(state)

    response = connection.in_data_exchange(connection_options, device_id, cmd, data)

    {:reply, response, %{state | power_mode: new_power_mode}}
  end

  def handle_call({:in_list_passive_target, max_targets}, _from, state = %{connection: connection, connection_options: connection_options, target_type: target_type}) do

    with {:ok, target_byte} <- get_target_type(target_type) do
      new_power_mode = connection.wakeup(state)
      response = connection.in_list_passive_target(connection_options, target_byte, max_targets)

      {:reply, response, %{state | power_mode: new_power_mode}}
    else
      error -> error
    end
  end

  def handle_call({:in_auto_poll, poll_number, period, type}, _from, state = %{connection: connection, connection_options: connection_options}) do
    new_power_mode = connection.wakeup(state)

    response = connection.in_auto_poll(connection_options, poll_number, period, type)

    {:reply, response, %{state | power_mode: new_power_mode, polling: true, poll_number: poll_number, poll_period: period, poll_type: type}}
  end

  # def handle_cast(:in_jump_for_dep, state = %{uart_pid: uart_pid}) do
  #   new_power_mode = wakeup(state)

  #   in_jump_for_dep_command = in_auto_poll_request_frame(poll_number, period, type)
  #   write_bytes(uart_pid, in_jump_for_dep_command)

  #   {:noreply, %{state | power_mode: new_power_mode}}
  # end

  # def handle_cast(:stop_target_detection, state = %{uart_pid: uart_pid, polling: true}) do
  #   # send ACK frame to cancel last command
  #   write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
  #   {:noreply, %{state | polling: false, poll_number: nil, poll_period: nil, poll_type: nil}}
  # end

  # def handle_cast(:stop_target_detection, state = %{detection_ref: nil}) do
  #   Logger.error("Target detection has not been started")
  #   {:noreply, state}
  # end

  # def handle_cast(:stop_target_detection, state = %{uart_pid: uart_pid, detection_ref: detection_ref}) when detection_ref != nil do
  #   Process.cancel_timer(detection_ref)
  #   # send ACK frame to cancel last command
  #   write_bytes(uart_pid, <<0x00, 0x00, 0xFF, @ack_frame, 0x00>>)
  #   {:noreply, %{state | detection_ref: nil, current_cards: nil}}
  # end

  # def handle_cast(:start_target_detection, state = %{detection_ref: detection_ref}) when detection_ref != nil do
  #   Logger.error("Target detection has already been started")
  #   {:noreply, state}
  # end

  # def handle_cast(:start_target_detection, state = %{polling: true}) do
  #   Logger.error("Target detection has already been started")
  #   {:noreply, state}
  # end

  # def handle_cast(:start_target_detection, state) do
  #   Logger.debug("Starting target detection")

  #   in_auto_poll(255, 1, 0)

  #   {:noreply, state}
  # end

  # def handle_info(:detect_target, state = %{uart_pid: uart_pid, target_type: target_type, current_cards: current_cards, detection_interval: detection_interval, read_timeout: read_timeout, handler: handler}) do
  #   new_power_mode = wakeup(state)

  #   new_state =
  #     with {:ok, target_byte} <- get_target_type(target_type),
  #          {:ok, card} <- detect_card(uart_pid, target_byte, 1, read_timeout, handler) do
  #       if current_cards != card do
  #         Process.spawn(handler, :handle_event, [:cards_detected, card], [])
  #         # receive do
  #         #   {:DOWN, ^reference, :process, ^pid, _} -> :ok
  #         #   unknown -> Logger.info("PACKET: #{inspect unknown}")
  #         # end
  #       end
  #       %{state | current_cards: card}
  #     else
  #       _ ->
  #         if current_cards != nil do
  #           Process.spawn(handler, :handle_event, [:cards_lost, current_cards], [])
  #         end
  #         %{state | current_cards: nil}
  #     end

  #   detection_ref = Process.send_after(self(), :detect_target, detection_interval)

  #   {:noreply, %{new_state | power_mode: new_power_mode, detection_ref: detection_ref}}
  # end

  # def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 0, _rest::bitstring>>},
  #   state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
  #   Logger.debug("Received in_auto_poll frame on #{inspect com_port} with no cards")

  #   if polling do
  #     if current_cards != nil do
  #       Process.spawn(handler, :handle_event, [:cards_lost, current_cards], [])
  #     end

  #     handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
  #   else
  #     {:noreply, %{state | current_cards: nil}}
  #   end
  # end

  # def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 1, in_auto_poll_response(_type, message), _padding::bitstring>>},
  #   state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
  #   Logger.debug("Received in_auto_poll frame on #{inspect com_port} with message: #{inspect message}")

  #   detected = apply(handler, :handle_detection, [1, [message]])

  #   if polling do
  #     with {:ok, cards} <- detected do
  #       if current_cards !== cards do
  #         Process.spawn(handler, :handle_event, [:cards_detected, cards], [])
  #       end
  #       handle_cast({:in_auto_poll, 7, period, type}, %{state | current_cards: cards})
  #     else
  #       _ ->
  #         handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
  #     end
  #   else
  #     {:noreply, state}
  #   end
  # end

  # def handle_info({:circuits_uart, com_port, <<0xD5, 0x61, 2, in_auto_poll_response(_type1, message1), in_auto_poll_response(_type2, message2), _padding::bitstring>>},
  #   state = %{handler: handler, polling: polling, poll_number: _poll_number, poll_period: period, poll_type: type, current_cards: current_cards}) do
  #   Logger.debug("Received in_auto_poll frame on #{inspect com_port} with two cards with message: #{inspect message1} and #{inspect message2}")

  #   detected = apply(handler, :handle_detection, [2, [message1, message2]])

  #   if polling do
  #     with {:ok, cards} <- detected do
  #       if current_cards !== cards do
  #         Process.spawn(handler, :handle_event, [:cards_detected, cards], [])
  #       end
  #       handle_cast({:in_auto_poll, 7, period, type}, %{state | current_cards: cards})
  #     else
  #       _ ->
  #         handle_cast({:in_auto_poll, 255, period, type}, %{state | current_cards: nil})
  #     end
  #   else
  #     {:noreply, state}
  #   end
  # end

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
