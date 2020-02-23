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

  defp get_hardware_product(<<0x01>> = byte), do: {byte, "MIFARE DESFire native IC (physical card)"}
  defp get_hardware_product(<<0x08>> = byte), do: {byte, "MIFARE DESFire Light native IC (physical card) "}
  defp get_hardware_product(<<0x81>> = byte), do: {byte, "MIFARE DESFire implementation on microcontroller (physical card)"}
  defp get_hardware_product(<<0x83>> = byte), do: {byte, "MIFARE DESFire implementation on microcontroller (physical card)"}
  defp get_hardware_product(<<0x91>> = byte), do: {byte, "MIFARE DESFire applet on Java card / secure element"}
  defp get_hardware_product(<<0xA1>> = byte), do: {byte, "MIFARE DESFire HCE (MIFARE 2GO)"}
  defp get_hardware_product(byte), do: {byte, "Unknown"}

  def parse_get_version(<<  hardware_vendor_id::binary-size(1),
                            hardware_type::binary-size(1),
                            hardware_subtype::binary-size(1),
                            hardware_version_major::binary-size(1),
                            hardware_version_minor::binary-size(1),
                            hardware_storage_size::binary-size(1),
                            hardware_protocol::binary-size(1),
                            software_vendor_id::binary-size(1),
                            software_type::binary-size(1),
                            software_subtype::binary-size(1),
                            software_version_major::binary-size(1),
                            software_version_minor::binary-size(1),
                            software_storage_size::binary-size(1),
                            software_protocol::binary-size(1),
                            uid::binary-size(7),
                            batch_number::binary-size(5),
                            production_week::binary-size(1),
                            production_year::binary-size(1),
                        >>) do
    {:ok,
      %{
        hardware_vendor_id: hardware_vendor_id,
        hardware_type: get_hardware_product(hardware_type),
        hardware_subtype: hardware_subtype,
        hardware_version_major: hardware_version_major,
        hardware_version_minor: hardware_version_minor,
        hardware_storage_size: hardware_storage_size,
        hardware_protocol: hardware_protocol,
        software_vendor_id: software_vendor_id,
        software_type: software_type,
        software_subtype: software_subtype,
        software_version_major: software_version_major,
        software_version_minor: software_version_minor,
        software_storage_size: software_storage_size,
        software_protocol: software_protocol,
        uid: uid,
        batch_number: batch_number,
        production_week: Base.encode16(production_week),
        production_year: Base.encode16(production_year)
      }
    }
  end
  def parse_get_version(_) do
    {:error, :failed_to_parse}
  end
end
