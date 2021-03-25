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

    # If any of the cards are authenticated
    if authenticated do
      # Do something, in my case i'm unlocking a door
      DoorService.unlock()
    end

    {:noreply, %{data | detected_cards: detected_cards, connection_options: %{data.connection_options | power_mode: new_power_mode}}}
  end

  # Handle card lost event
  def handle_event(:cards_lost, lost_cards, _client, data) do

    # log cards no longer detected by the PN532
    ids = for %{nfcid: identifier, type: type} <- lost_cards do
      "#{inspect type} card with ID: #{inspect Base.encode16(identifier)}"
    end

    Logger.info("Lost connection with #{Enum.join(ids, " and ")}")

    {:noreply, data}
  end
end
```

## Create card detector

```elixir
defmodule CardService.CardDetector do
  require Logger

  # this is the default access key for mifare
  @default_keys [<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>]

  def detect_cards(client, data, cards, key) do
    detect_cards(client, data, cards, key, [])
  end

  def detect_cards(client, data, [%{tg: _target_number, nfcid: _identifier} = card | rest], key, acc) do
    with {:ok, authenticated_card, new_client, new_data} <- authenticate_card(client, data, card, key) do
      detect_cards(new_client, new_data, rest, key, [authenticated_card | acc])
    else
      {:error, message, result, new_client, new_data} ->
        Logger.error("Error occured authenticating card: #{inspect message}")
        detect_cards(new_client, new_data, rest, key, [result | acc])
    end
  end

  def detect_cards(client, data, [unsupported | rest], key, acc) when is_map(unsupported) do
    detect_cards(client, data, rest, key, acc)
  end

  def detect_cards(_, _, _, _, acc) do
    acc
  end

  def authenticate_card(client, data, %{tg: target_number, nfcid: identifier} = card, key) do
    Logger.info("About to try authenticate key: #{inspect key}")
    with :ok <- client.deselect(data, target_number),
         :ok <- client.select(data, target_number),
         :ok <- client.authenticate(data, target_number, 1, :key_a, key, identifier) do
      result =
        with {:load_secure_code, {:ok, user_token}} <- {:load_secure_code, CardService.get_card_token(identifier)},
             {:read_secure_code, {:ok, secure_code}} <- {:read_secure_code, client.read(data, target_number, 1)},
             {:verify_secure_code, {true, ^user_token, ^secure_code}} <- {:verify_secure_code, {user_token === secure_code, user_token, secure_code}} do

        card = card
        |> Map.put(:authenticated, :success)
        |> Map.put(:key, key)
        |> Map.put(:access_code, secure_code)

        with {:ok, user} <- CardService.get_card_user(identifier) do
          Map.put(card, :user, user)
        else
          _ ->
            card
        end
      else
        {:load_secure_code, error} ->
          Logger.error("Error occured loading secure code: #{inspect error}")
          card
          |> Map.put(:authenticated, :failure)
          |> Map.put(:key, key)
          |> Map.put(:error, error)
        {:read_secure_code, error} ->
          Logger.error("Error occured reading secure code on card: #{inspect error}")
          card
          |> Map.put(:authenticated, :failure)
          |> Map.put(:key, key)
          |> Map.put(:error, error)
        {:verify_secure_code, {result, user_token, secure_code}} ->
          Logger.error("Secure Codes do not match #{inspect user_token} != #{inspect secure_code}")
          card
          |> Map.put(:authenticated, :failure)
          |> Map.put(:key, key)
          |> Map.put(:error, :secure_code_invalid)
        {:error, error} ->
          Logger.error("Error occured reading access code: #{inspect error}")
          card
          |> Map.put(:authenticated, :failure)
          |> Map.put(:error, error)
      end

      authenticate_card(result, client, data)
    else
      {:error, {:mifare_authentication_error, _}} ->
        authenticate_card_defaults(client, data, card, @default_keys)
      {:error, error} ->
        Logger.error("Error occured authenticating card: #{inspect error}")
        card
        |> Map.put(:authenticated, :failure)
        |> Map.put(:error, error)
        |> authenticate_card(client, data)
    end
  end

  defp authenticate_card_defaults(client, data, %{tg: target_number, nfcid: identifier} = card, [first_key | rest]) do
    Logger.info("About to try default authenticate key: #{inspect first_key}")
    with  :ok <- client.deselect(data, target_number),
          :ok <- client.select(data, target_number),
          :ok <- client.authenticate(data, target_number, 1, :key_a, first_key, identifier) do
      card
      |> Map.put(:authenticated, :default)
      |> Map.put(:key, first_key)
      |> authenticate_card(client, data)
    else
      {:error, {:mifare_authentication_error, _}} ->
        authenticate_card_defaults(client, data, card, rest)
      {:error, error} ->
        Logger.error("Error occured authenticating card: #{inspect error}")
        card
        |> Map.put(:authenticated, :failure)
        |> Map.put(:error, error)
        |> authenticate_card(client, data)
    end
  end

  defp authenticate_card_defaults(client, data, card, []) do
    card
    |> Map.put(:authenticated, :failure)
    |> Map.put(:error, :unknown_key_a)
    |> authenticate_card(client, data)
  end

  defp authenticate_card(%{error: message} = result, client, data) do
    {:error, message, result, client, data}
  end

  defp authenticate_card(result, client, data) do
    {:ok, result, client, data}
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