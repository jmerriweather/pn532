defmodule PN532.Handler do
  @doc """
  Is called when setting PN532 server
  """
  @callback setup(map) :: :ok
  @doc """
  Is called when connected to the card reader
  """
  @callback connected(map) :: :ok
  @doc """
  Provides the ability to parse the card data and form a card
  """
  @callback handle_detection(integer, [binary]) :: {:ok, [map]} | {:error, term}
  @doc """
  Provides a place to handle when an event happens, such as a card is detected
  """
  @callback handle_event(atom, [map]) :: :ok | {:error, any}

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour PN532.Handler
      require Logger
      require PN532.Connection.Frames
      import PN532.Connection.Frames

      @doc false
      def setup(state) do
        Logger.info("PN532.Handler initi")
      end

      def connected(connect_info) do
        with %{port: port, firmware_version: version} <- connect_info do
          Logger.info("Connected on port #{inspect port} with firmware #{inspect version}")
        end
      end

      def handle_detection(_, card_data) do
        cards = parse_card(card_data, [])
        {:ok, cards}
      end

      def parse_card([<<dep_target(target_number, nfcid3i, didt, bst, brt, time_out, ppt, geneal_info)>> | rest], acc) do
        card = %{tg: target_number, nfcid3i: nfcid3i, didt: didt, bst: bst, brt: brt, time_out: time_out, ppt: ppt, geneal_info: geneal_info, type: :dep}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<dep_target_short(target_number, nfcid3i, didt, bst, brt)>> | rest], acc) do
        card = %{tg: target_number, nfcid3i: nfcid3i, didt: didt, bst: bst, brt: brt, type: :dep}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<iso_14443_type_a_target(target_number, sens_res, sel_res, identifier)>> | rest], acc) do
        Logger.debug("Received Mifare Type A card detection with ID: #{inspect Base.encode16(identifier)}")
        card = %{tg: target_number, sens_res: sens_res, sel_res: sel_res, nfcid: identifier, type: :iso_14443_type_a}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<iso_14443_type_b_target(target_number, atqb, attrib_res)>> | rest], acc) do
        Logger.debug("Received Mifare Type B card detection")
        card = %{tg: target_number, atqb: atqb, attrib_res: attrib_res, type: :iso_14443_type_b}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<feliCa_20_target(target_number, response_code, nfcid2t, pad, syst_code)>> | rest], acc) do
        Logger.debug("Received Felica 20byte card detection")
        card = %{tg: target_number, response_code: response_code, nfcid2t: nfcid2t, pad: pad, syst_code: syst_code, type: :felica}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<feliCa_18_target(target_number, response_code, nfcid2t, pad)>> | rest], acc) do
        Logger.debug("Received Felica 18byte card detection")
        card = %{tg: target_number, response_code: response_code, nfcid2t: nfcid2t, pad: pad, type: :felica}
        parse_card(rest, [card | acc])
      end

      def parse_card([<<jewel_target(target_number, sens_res, jewelid)>> | rest], acc) do
        Logger.debug("Received Jewel card detection with ID: #{inspect Base.encode16(jewelid)}")
        card = %{tg: target_number, sens_res: sens_res, jewelid: jewelid, type: :jewel}
        parse_card(rest, [card | acc])
      end

      def parse_card([data], acc) do
        Logger.warn("Unknown data #{inspect data}")
        acc
      end

      def parse_card(_, acc) do
        acc
      end

      def detect_id([%{nfcid: identifier, type: type} | rest], acc) do
        detect_id(rest, [%{identifier: identifier, type: type} | acc])
      end

      def detect_id([%{nfcid2t: identifier, type: type} | rest], acc) do
        detect_id(rest, [%{identifier: identifier, type: type} | acc])
      end

      def detect_id([%{nfcid3i: identifier, type: type} | rest], acc) do
        detect_id(rest, [%{identifier: identifier, type: type} | acc])
      end

      def detect_id([%{jewelid: identifier, type: type} | rest], acc) do
        detect_id(rest, [%{identifier: identifier, type: type} | acc])
      end
      def detect_id(_, acc) do
        acc
      end

      @doc false
      def handle_event(:cards_detected, cards) do
        ids = for %{identifier: identifier, type: type} <- detect_id(cards, []) do
          "#{inspect type} card with ID: #{inspect Base.encode16(identifier)}"
        end
        Logger.info("Detected new #{Enum.join(ids, " and ")}")
      end

      @doc false
      def handle_event(:cards_lost, cards) do
        ids = for %{identifier: identifier, type: type} <- detect_id(cards, []) do
          "#{inspect type} card with ID: #{inspect Base.encode16(identifier)}"
        end
        Logger.info("Lost connection with #{Enum.join(ids, " and ")}")
      end

      defoverridable PN532.Handler
    end
  end
end

