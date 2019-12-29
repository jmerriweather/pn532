defmodule PN532.Client.Disconnected do
  @moduledoc """
  Functions for when we are in the connected state
  """
  require Logger

  def disconnected(_, _, _) do
    :keep_state_and_data
  end
end
