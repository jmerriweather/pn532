defmodule PN532.Connection.Desfire do
  use Bitwise
  require Logger



  def apdu_response_frame(apdu) do
    data_length = byte_size(apdu) - 2
    <<data::binary-size(data_length), sw1::binary-size(1), sw2::binary-size(1)>> = apdu
    case sw1 <> sw2 do
      <<0x91, 0xAF>> -> {:more, data}
      <<0x91, 0x00>> -> {:complete, data}
      _ -> {:unknown, data}
    end
  end

end
