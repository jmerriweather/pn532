defmodule PN532.Handler do
  @doc """
  Is called when setting up the connection to the card reader
  """
  @callback setup(map) :: :ok
  @doc """
  Provides the ability to parse the card data and form a card
  """
  @callback handle_detection(integer, binary) :: {:ok, map} | {:ok, [map]} | {:error, term}
  @doc """
  Provides a place to handle when an event happens, such as a card is detected
  """
  @callback handle_event(any, any) :: :ok | {:error, any}

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour PN532.Handler
      require Logger
      require PN532.Client.Frames
      import PN532.Client.Frames

      @doc false
      def setup(state) do
        Logger.info("PN532.Handler initi")
      end

      @doc false
      def handle_detection(1, card_data) do
        case card_data do
          iso_14443_type_a_target(target_number, sens_res, sel_res, identifier) ->
            Logger.debug("Received Mifare Type A card detection with ID: #{inspect Base.encode16(identifier)}")
            {:ok, %{tg: target_number, sens_res: sens_res, sel_res: sel_res, nfcid: identifier}}
          iso_14443_type_b_target(target_number, atqb, attrib_res) ->
            Logger.debug("Received Mifare Type B card detection")
            {:ok, %{tg: target_number, atqb: atqb, attrib_res: attrib_res}}
          feliCa_18_target(target_number, response_code, nfcid2t, pad) ->
            Logger.debug("Received Felica 18byte card detection")
            {:ok, %{tg: target_number, response_code: response_code, nfcid2t: nfcid2t, pad: pad}}
          feliCa_20_target(target_number, response_code, nfcid2t, pad, syst_code) ->
            Logger.debug("Received Felica 20byte card detection")
            {:ok, %{tg: target_number, response_code: response_code, nfcid2t: nfcid2t, pad: pad, syst_code: syst_code}}
          jewel_target(target_number, sens_res, jewelid) ->
            Logger.debug("Received Jewel card detection with ID: #{inspect Base.encode16(jewelid)}")
            {:ok, %{tg: target_number, sens_res: sens_res, jewelid: jewelid}}
        end
      end

      @doc false
      def handle_detection(2, card_data) do
        case card_data do
          <<iso_14443_type_a_target(target_number1, sens_res1, sel_res1, identifier1), iso_14443_type_a_target(target_number2, sens_res2, sel_res2, identifier2)>> ->
            Logger.debug("Received Mifare Type A card detection with ID: #{inspect Base.encode16(identifier1)} and #{inspect Base.encode16(identifier2)} ")
            {:ok, [
              %{tg: target_number1, sens_res: sens_res1, sel_res: sel_res1, nfcid: identifier1},
              %{tg: target_number2, sens_res: sens_res2, sel_res: sel_res2, nfcid: identifier2}
            ]}
          <<iso_14443_type_b_target(target_number1, atqb1, attrib_res1), iso_14443_type_b_target(target_number2, atqb2, attrib_res2)>> ->
            Logger.debug("Received Mifare Type B card detection")
            {:ok, [
              %{tg: target_number1, atqb: atqb1, attrib_res: attrib_res1},
              %{tg: target_number2, atqb: atqb2, attrib_res: attrib_res2}
            ]}
          <<feliCa_18_target(target_number1, response_code1, nfcid2t1, pad1), feliCa_18_target(target_number2, response_code2, nfcid2t2, pad2)>> ->
            Logger.debug("Received two Felica 18byte card detection")
            {:ok, [
              %{tg: target_number1, response_code: response_code1, nfcid2t: nfcid2t1, pad: pad1},
              %{tg: target_number2, response_code: response_code2, nfcid2t: nfcid2t2, pad: pad2}
            ]}
          <<feliCa_20_target(target_number1, response_code1, nfcid2t1, pad1, syst_code1), feliCa_20_target(target_number2, response_code2, nfcid2t2, pad2, syst_code2)>> ->
            Logger.debug("Received two Felica 20byte card detection")
            {:ok, [
              %{tg: target_number1, response_code: response_code1, nfcid2t: nfcid2t1, pad: pad1, syst_code: syst_code1},
              %{tg: target_number2, response_code: response_code2, nfcid2t: nfcid2t2, pad: pad2, syst_code: syst_code2}
            ]}
        end
      end

      @doc false
      def handle_event(:cards_detected, _card = %{nfcid: identifier}) do
        Logger.info("Detected new Mifare card with ID: #{Base.encode16(identifier)}")
      end

      @doc false
      def handle_event(:cards_lost, _card = %{nfcid: identifier}) do
        Logger.info("Lost connection with Mifare card with ID: #{Base.encode16(identifier)}")
      end

      @doc false
      def handle_event(:cards_detected, _card = [%{nfcid: identifier1}, %{nfcid: identifier2}]) do
        Logger.info("Detected new Mifare card with ID: #{Base.encode16(identifier1)} and #{Base.encode16(identifier2)}")
      end

      @doc false
      def handle_event(:cards_lost, _card = [%{nfcid: identifier1}, %{nfcid: identifier2}]) do
        Logger.info("Lost connection with Mifare card with ID: #{Base.encode16(identifier1)} and #{Base.encode16(identifier2)}")
      end

      defoverridable PN532.Handler
    end
  end
end
