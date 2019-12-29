defmodule PN532.Client do
  use GenStateMachine
  require Logger

  @ack_frame <<0x00, 0xFF>>
  @nack_frame <<0xFF, 0x00>>

  def open(com_port, uart_speed \\ nil) do
    GenStateMachine.call(__MODULE__, {:open, com_port, uart_speed})
  end

  def close() do
    GenStateMachine.call(__MODULE__, :close)
  end

  def get_current_cards() do
    GenStateMachine.call(__MODULE__, :get_current_cards)
  end

  def get_detected_cards() do
    GenStateMachine.call(__MODULE__, :get_detected_cards)
  end

  def start_target_detection() do
    GenStateMachine.cast(__MODULE__, :start_target_detection)
  end

  def stop_target_detection() do
    GenStateMachine.cast(__MODULE__, :stop_target_detection)
  end

  def authenticate(device_id, block, key_type, key, card_id) do
    command =
      case key_type do
        :key_a -> 0x60
        :key_b -> 0x61
      end
    data = <<block>> <> key <> card_id

    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, command, data})
  end

  def select(device_id) do
    GenStateMachine.call(__MODULE__, {:in_select, device_id})
  end

  def deselect(device_id) do
    GenStateMachine.call(__MODULE__, {:in_deselect, device_id})
  end

  def read(device_id, block) do
    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, 0x30, <<block>>})
  end

  def write16(device_id, block, <<data::binary-size(16)>>) do
    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, 0xA0, <<block>> <> data})
  end

  def write4(device_id, block, <<data::binary-size(4)>>) do
    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, 0xA2, <<block>> <> data})
  end

  def in_data_exchange(device_id, cmd, addr, data) do
    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, cmd, <<addr, data>>})
  end

  def in_data_exchange(device_id, cmd, data) do
    GenStateMachine.call(__MODULE__, {:in_data_exchange, device_id, cmd, data})
  end

  def in_auto_poll(poll_number, period, type) do
    GenStateMachine.cast(__MODULE__, {:in_auto_poll, poll_number, period, type})
  end

  def get_firmware_version() do
    GenStateMachine.call(__MODULE__, :get_firmware_version)
  end

  def get_general_status() do
    GenStateMachine.call(__MODULE__, :get_general_status)
  end

  def in_list_passive_target(max_targets) do
    GenStateMachine.call(__MODULE__, {:in_list_passive_target, max_targets})
  end

  def set_serial_baud_rate(baud_rate) do
    GenStateMachine.call(__MODULE__, {:set_serial_baud_rate, baud_rate})
  end

  # GenStateMachine

  def child_spec(args) do
    %{id: __MODULE__, type: :worker, start: {__MODULE__, :start_link, [args]}}
  end

  # API
  def start_link(init_arg) do
    GenStateMachine.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(init_arg) do
    handler = Map.get(init_arg, :handler, PN532.DefaultHandler)
    target_type = Map.get(init_arg, :target_type, :iso_14443_type_a)
    connection_options = Map.get(init_arg, :connection_options, %{})

    uart_port = Map.get(init_arg, :uart_port, nil)

    uart_pid = Map.get(connection_options, :uart_pid, PN532.UART)
    uart_speed = Map.get(connection_options, :uart_speed, 115200)
    read_timeout = Map.get(connection_options, :read_timeout, 1500)

    connection = Map.get(init_arg, :connection, PN532.Connection.Uart)
    {:ok, :initialising,
      %{
          connection: connection,
          connection_options: %{
            uart_pid: uart_pid,
            uart_port: uart_port,
            uart_speed: uart_speed,
            uart_open: false,
            read_timeout: read_timeout,
            power_mode: :low_v_bat
          },
          handler: handler,
          target_type: target_type,
          current_cards: nil,
          detected_cards: nil,
          polling: false,
          poll_number: 255,
          poll_period: 1,
          poll_type: 0
      },
      [{:next_event, :internal, :handle_setup}]
    }
  end

  def handle_event({:call, from}, :get_current_cards, _, %{current_cards: cards}) do
    {:keep_state_and_data, [{:reply, from, {:ok, cards}}]}
  end

  def handle_event({:call, from}, :get_detected_cards, _, %{detected_cards: cards}) do
    {:keep_state_and_data, [{:reply, from, {:ok, cards}}]}
  end

  def handle_event({:call, from}, :open, state, _data) when state != :disconnected do
    {:keep_state_and_data, [{:reply, from, {:error, :already_open}}]}
  end

  def handle_event({:call, from}, :open, _, %{connection_options: %{uart_open: true}}) do
    {:keep_state_and_data, [{:reply, from, {:error, :already_open}}]}
  end

  def handle_event({:call, from}, {:open, com_port, nil}, _, data = %{connection_options: connection_options}) do
    new_connection_options = %{connection_options | uart_port: com_port}
    {:next_state, :connecting, %{data | connection_options: new_connection_options}, [{:next_event, :internal, {:auto_connect, from}}]}
  end

  def handle_event({:call, from}, {:open, com_port, uart_speed}, _, data = %{connection_options: connection_options}) do
    new_connection_options = %{connection_options | uart_port: com_port, uart_speed: uart_speed}
    {:next_state, :connecting, %{data | connection_options: new_connection_options}, [{:next_event, :internal, {:auto_connect, from}}]}
  end

  def handle_event({:call, from}, _, _state, %{connection_options: %{uart_open: false}}) do
    {:keep_state_and_data, [{:reply, from, {:error, :not_open}}]}
  end

  def handle_event({:call, from}, :close, _, data = %{connection: connection, connection_options: connection_options}) do
    response = connection.close(connection_options)
    {:next_state, :disconnected, %{data | connection_options: %{connection_options | uart_open: false}}, [{:reply, from, response}]}
  end

  def handle_event(:info, {:circuits_uart, com_port, <<0x7F>>}, _, _data) do
    Logger.error("Received Error frame on #{inspect com_port}")
    :keep_state_and_data
  end

  def handle_event(:info, {:circuits_uart, com_port, @ack_frame}, _, _data) do
    Logger.debug("Received ACK frame on #{inspect com_port}")
    :keep_state_and_data
  end

  def handle_event(:info, {:circuits_uart, com_port, @nack_frame}, _, _data) do
    Logger.debug("Received NACK frame on #{inspect com_port}")
    :keep_state_and_data
  end

  def handle_event(type, event, state, data) do
    Logger.debug("#{inspect __MODULE__} State: #{inspect(type)}, #{inspect(event)}, #{inspect(state)}")

    apply(__MODULE__, state, [type, event, data])
  end


  defdelegate initialising(type, event, data), to: PN532.Client.Initialising
  defdelegate connecting(type, event, data), to: PN532.Client.Connecting
  defdelegate connected(type, event, data), to: PN532.Client.Connected
  defdelegate disconnected(type, event, data), to: PN532.Client.Disconnected
  defdelegate detecting(type, event, data), to: PN532.Client.Detecting
  defdelegate detected(type, event, data), to: PN532.Client.Detected


  # def handle_cast({:in_auto_poll, poll_number, period, type}, state = %{connection: connection, connection_options: connection_options}) do
  #   new_power_mode = connection.wakeup(state)

  #   connection.in_auto_poll(connection_options, poll_number, period, type)

  #   {:noreply, %{state | power_mode: new_power_mode, polling: true, poll_number: poll_number, poll_period: period, poll_type: type}}
  # end

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

  # def handle_info({:circuits_uart, com_port, <<0x7F>>}, state) do
  #   Logger.error("Received Error frame on #{inspect com_port}")
  #   {:noreply, state}
  # end

  # def handle_info({:circuits_uart, com_port, @ack_frame}, state) do
  #   Logger.debug("Received ACK frame on #{inspect com_port}")
  #   {:noreply, state}
  # end

  # def handle_info({:circuits_uart, com_port, @nack_frame}, state) do
  #   Logger.debug("Received NACK frame on #{inspect com_port}")
  #   {:noreply, state}
  # end
end
