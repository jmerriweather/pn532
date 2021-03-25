# PN532

## Hardware

Any PN532 board should work as long as it supports UART.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pn532` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pn532, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pn532](https://hexdocs.pm/pn532).

## How to use

### Create Card Handler

```elixir
defmodule CardService.CardHandler do
  use PN532.Handler

  # In the setup handler you can get things ready, I use this to load a
  # custom access key into the database if one doesn't exist
  def setup(_state) do

    # Check if access key is store in database
    with {:ok, access_key} <- CardService.get_access_key(:key_a) do
      access_key
    else
      {:error, :empty} ->
        # If no access key in database, get the one from the applicaiton config
        card_service_config = Application.get_env(:card_service, :config)
        with {:ok, secret} <- Keyword.get(card_service_config, :secret) |> Base.decode64() do

          # Save access key into the database
          CardService.set_access_key(:key_a, secret)
        end
      {:error, error} ->
        throw(error)
    end
  end

  # The connected handler function runs when your application is connected to the PN532
  def connected(connect_info) do

    # Get information about the PN532
    with %{port: port, firmware_version: %{version: version, revision: revision, ic_version: ic_version}} <- connect_info do
      Logger.info("Connected on port #{inspect port} with firmware version #{version}.#{revision}, IC version #{ic_version}")
    end

    # Begin target detection, this will poll the PN532 for cards
    :ok = PN532.Client.start_target_detection()
  end

  # Handle card detected event
  def handle_event(:cards_detected, cards, client, data) do
    # Make sure PN532 is awake
    new_power_mode = client.wakeup(data)

    # Get access key from database
    {:ok, key_a} = CardService.get_access_key(:key_a)

    Logger.info("About to use key_a #{inspect key_a}")
    # This will call out to a function to attempt to authenticate the card using the access key,
    # otherwise will try the default keys. I'll document this module next.
    detected_cards = CardService.CardDetector.detect_cards(client, data, cards, key_a)

    Logger.info("decoded: #{inspect detected_cards}")
    # Log each card detected
    ids = for %{ nfcid: identifier, type: type } <- detected_cards do
      "#{inspect type} card with ID: #{inspect Base.encode16(identifier)}"
    end

    # Check if any of the cards are authenticated
    authenticated = Enum.any?(detected_cards, fn card -> card.authenticated == :success end)

    if authenticated do
      DoorService.unlock()
    end

    pubsub_name = Application.get_env(:ui, UiWeb.Endpoint) |> Keyword.get(:pubsub) |> Keyword.get(:name)

    Phoenix.PubSub.broadcast(pubsub_name, "cards_detected", %{topic: "cards_detected", payload: detected_cards})
    Logger.info("Detected new #{Enum.join(ids, " and ")}")

    {:noreply, %{data | detected_cards: detected_cards, connection_options: %{data.connection_options | power_mode: new_power_mode}}}
  end

  def handle_event(:cards_lost, lost_cards, _client, data) do
    ids = for %{nfcid: identifier, type: type} <- lost_cards do
      "#{inspect type} card with ID: #{inspect Base.encode16(identifier)}"
    end

    pubsub_name = Application.get_env(:ui, UiWeb.Endpoint) |> Keyword.get(:pubsub) |> Keyword.get(:name)

    Phoenix.PubSub.broadcast(pubsub_name, "cards_lost", %{topic: "cards_lost", payload: lost_cards})
    Logger.info("Lost connection with #{Enum.join(ids, " and ")}")

    {:noreply, data}
  end
end
```


```elixir
defmodule CardService.Supervisor do
  use Supervisor
  require Logger

  def start_link(args) do
    Logger.info("about to start #{inspect __MODULE__}")
    Supervisor.start_link(__MODULE__, [args], name: __MODULE__)
  end

  def init([args]) do
    card_service_config = Application.get_env(:card_service, :config)
    uart_port = Keyword.get(card_service_config, :uart_port)
    uart_speed = Keyword.get(card_service_config, :uart_speed)

    children = [
      {PN532.Supervisor, [%{target_type: :iso_14443_type_a, handler: CardService.CardHandler, uart_port: uart_port, uart_speed: uart_speed}]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```