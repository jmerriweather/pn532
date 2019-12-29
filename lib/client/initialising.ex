defmodule PN532.Client.Initialising do
  @moduledoc """
  Functions for when we are in the initialising state
  """
  require Logger

  def initialising(:internal, :handle_setup, data = %{handler: handler}) do
    apply(handler, :setup, [data])

    {:next_state, :connecting, data, {:next_event, :internal, :auto_connect}}
  end
end
