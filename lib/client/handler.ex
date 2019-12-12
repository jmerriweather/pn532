defmodule PN532.Handler do
  @doc """
  Is called when setting up the connection to the card reader
  """
  @callback setup(map) :: :ok
  @doc """
  Provides the ability to parse the card data and form a card
  """
  @callback handle_detection(integer, binary) :: {:ok, term} | {:error, term}
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
      def handle_detection(total_cards, card_data) when is_list(card_data) do
        cards = for <<iso_14443_type_a_target(target_number, sens_res, sel_res, identifier) <- card_data>> do
          %{tg: target_number, sens_res: sens_res, sel_res: sel_res, nfcid: identifier}
        end
        identifiers_in_base16 = cards |> Enum.map(fn(x) -> Base.encode16(x.nfcid) end)
        Logger.debug("Received '#{inspect total_cards}' new Mifare cards with IDs: #{inspect identifiers_in_base16}")
        {:ok, cards}
      end

      @doc false
      def handle_detection(1, iso_14443_type_a_target(target_number, sens_res, sel_res, identifier)) do
        Logger.debug("Received Mifare card detection with ID: #{inspect Base.encode16(identifier)}")
        {:ok, %{tg: target_number, sens_res: sens_res, sel_res: sel_res, nfcid: identifier}}
      end

      @doc false
      def handle_event(:card_detected, _card = %{nfcid: identifier}) do
        Logger.info("Detected new Mifare card with ID: #{Base.encode16(identifier)}")
      end

      @doc false
      def handle_event(:card_lost, _card = %{nfcid: identifier}) do
        Logger.info("Lost connection with Mifare card with ID: #{Base.encode16(identifier)}")
      end

      defoverridable PN532.Handler
    end
  end
end
