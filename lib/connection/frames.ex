defmodule PN532.Connection.Frames do
  use Bitwise
  require Logger

  defmacro iso_14443_type_a_target(target_number, sens_res, sel_res, identifier) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        unquote(sens_res)::binary-size(2),
        unquote(sel_res)::binary-size(1),
        id_length::integer-signed,
        unquote(identifier)::binary-size(id_length)
      >>
    end
  end

  defmacro iso_14443_type_b_target(target_number, atqb, attrib_res) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        unquote(atqb)::binary-size(12),
        id_length::integer-signed,
        unquote(attrib_res)::binary-size(id_length)
      >>
    end
  end

  defmacro feliCa_18_target(target_number, response_code, nfcid2t, pad) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        18,
        unquote(response_code)::binary-size(1),
        unquote(nfcid2t)::binary-size(8),
        unquote(pad)::binary-size(8),
      >>
    end
  end

  defmacro feliCa_20_target(target_number, response_code, nfcid2t, pad, syst_code) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        20,
        unquote(response_code)::binary-size(1),
        unquote(nfcid2t)::binary-size(8),
        unquote(pad)::binary-size(8),
        unquote(syst_code)::binary-size(2)
      >>
    end
  end

  defmacro jewel_target(target_number, sens_res, jewelid) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        unquote(sens_res)::binary-size(2),
        unquote(jewelid)::binary-size(4),
      >>
    end
  end

  def in_auto_poll_request_frame(poll_nr, period, type) do
    <<
      0x60,
      poll_nr,
      period,
      type
    >>
  end

  defmacro in_auto_poll_response(type, message) do
    quote do
      <<
        unquote(type)::binary-size(1),
        length::integer,
        unquote(message)::binary-size(length)
      >>
    end
  end

  def in_jump_for_dep_request_frame(act_pass, baud_rate, next, frames) do
    <<
      0x56,
      act_pass,
      baud_rate,
      next,
      frames
    >>
  end

  def generate_nfcid3i() do
    :crypto.strong_rand_bytes(10)
  end

  defmacro dep_target(target_number, nfcid3i, didt, bst, brt, time_out, ppt, geneal_info) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        unquote(nfcid3i)::binary-size(10),
        unquote(didt)::binary-size(1),
        unquote(bst)::binary-size(1),
        unquote(brt)::binary-size(1),
        unquote(time_out)::binary-size(1),
        unquote(ppt)::binary-size(1),
        unquote(geneal_info)::bitstring,
      >>
    end
  end

  defmacro dep_target_short(target_number, nfcid3i, didt, bst, brt) do
    quote do
      <<
        unquote(target_number)::integer-signed,
        unquote(nfcid3i)::binary-size(10),
        unquote(didt)::binary-size(1),
        unquote(bst)::binary-size(1),
        unquote(brt)::binary-size(1)
      >>
    end
  end

  defmacro firmware_version_response(ic_version, version, revision, support) do
    quote do
      <<
        0xD5, 0x03,
        unquote(ic_version)::binary-size(1),
        unquote(version)::integer-signed,
        unquote(revision)::integer-signed,
        unquote(support)::integer-signed
      >>
    end
  end

  defmacro get_general_status_response(err, field, number_of_targets, targets) do
    quote do
      <<
        0xD5, 0x05,
        unquote(err)::binary-size(1),
        unquote(field)::binary-size(1),
        unquote(number_of_targets)::integer,
        unquote(targets)
      >>
    end
  end

  def parse_general_status(<<err::binary-size(1), field::binary-size(1), target_number::integer, targets::binary>>) do
    targets_size = byte_size(targets)
    sam = binary_part(targets, targets_size - 1, 1)
    just_targets = binary_part(targets, 0, targets_size - 1)
    Logger.debug("Field: #{inspect field}")
    %{
      error: get_error(err),
      field_active: (if field == <<0x01>>, do: true, else: false),
      target_number: target_number,
      targets: case just_targets do
        <<target::integer, reception_bitrate::binary-size(1), transmission_bitrate::binary-size(1), modulation_type::binary-size(1)>> ->
          %{target: target, reception_bitrate: get_bitrate(reception_bitrate), transmission_bitrate: get_bitrate(transmission_bitrate), modulation_type: get_modulation_type(modulation_type)}
        <<target1::integer, reception_bitrate1::binary-size(1), transmission_bitrate1::binary-size(1), modulation_type1::binary-size(1),
          target2::integer, reception_bitrate2::binary-size(1), transmission_bitrate2::binary-size(1), modulation_type2::binary-size(1)>> ->
            [
              %{target: target1, reception_bitrate: get_bitrate(reception_bitrate1), transmission_bitrate: get_bitrate(transmission_bitrate1), modulation_type: get_modulation_type(modulation_type1)},
              %{target: target2, reception_bitrate: get_bitrate(reception_bitrate2), transmission_bitrate: get_bitrate(transmission_bitrate2), modulation_type: get_modulation_type(modulation_type2)}
            ]
        _ ->
          []
      end,
      sam: sam
    }
  end

  def get_target_type(target) do
    case target do
      :iso_14443_type_a -> {:ok, 0x00}
      :felica_212 -> {:ok, 0x01}
      :felica_424 -> {:ok, 0x02}
      :iso_14443_type_b -> {:ok, 0x03}
      :jewel -> {:ok, 0x04}
      _ -> {:error, :invalid_target_type}
    end
  end

  def get_bitrate(<<0x00>>), do: "106 kbps"
  def get_bitrate(<<0x01>>), do: "212 kbps"
  def get_bitrate(<<0x02>>), do: "424 kbps"

  def get_modulation_type(<<0x00>>), do: "Mifare"
  def get_modulation_type(<<0x10>>), do: "FeliCa"
  def get_modulation_type(<<0x01>>), do: "ISO/IEC18092 Active mode"
  def get_modulation_type(<<0x02>>), do: "Innovision Jewel tag"

  def get_error(error_byte) do
    case error_byte do
      <<0>> -> {:success, "No error"}
      0x01 -> {:target_timeout, "The target has not answered"}
      0x02 -> {:crc_error, "A CRC error has been detected by the CIU"}
      0x03 -> {:parity_error, "A Parity error has been detected by the CIU"}
      0x04 -> {:bit_count_error, "During an anti-collision/select operation (ISO/IEC14443-3 Type A and ISO/IEC18092 106 kbps passive mode), an erroneous Bit Count has been detected"}
      0x05 -> {:mifare_framing_error, "Framing error during Mifare operation"}
      0x06 -> {:abnormal_bit_collision, "An abnormal bit-collision has been detected during bit wise anti-collision at 106 kbps"}
      0x07 -> {:buffer_size_insufficient, "Communication buffer size insufficient"}
      0x09 -> {:rf_buffer_overflow, "RF Buffer overflow has been detected by the CIU (bit BufferOvfl of the register CIU_Error)"}
      0x0A -> {:rf_field_not_on_in_time, "In active communication mode, the RF field has not been switched on in time by the counterpart (as defined in NFCIP-1 standard)"}
      0x0B -> {:rf_protocol_error, "RF Protocol error"}
      0x0D -> {:temperature_error, "Temperature error: the internal temperature sensor has detected overheating, and therefore has automatically switched off the antenna drivers"}
      0x0E -> {:internal_buffer_overflow, "Internal buffer overflow"}
      0x10 -> {:invalid_parameter, "Invalid parameter (range, format, ...)"}
      0x12 -> {:dep_command_received_invalid, "The PN532 configured in target mode does not support the command received from the initiator (the command received is not one of the following: ATR_REQ, WUP_REQ, PSL_REQ, DEP_REQ, DSL_REQ, RLS_REQ"}
      0x13 -> {:dep_data_format_not_match_spec, "Mifare or ISO/IEC14443-4: The data format does not match to the specification. Depending on the RF protocol used, it can be: Bad length of RF received frame, Incorrect value of PCB or PFB, Incorrect value of PCB or PFB, NAD or DID incoherence."}
      0x14 -> {:mifare_authentication_error, "Mifare: Authentication error"}
      0x23 -> {:uid_check_byte_wrong, "ISO/IEC14443-3: UID Check byte is wrong"}
      0x25 -> {:dep_invalid_device_state, "Invalid device state, the system is in a state which does not allow the operation"}
      0x26 -> {:op_not_allowed, "Operation not allowed in this configuration (host controller interface)"}
      0x27 -> {:command_invalid_in_context, "This command is not acceptable due to the current context of the PN532 (Initiator vs. Target, unknown target number, Target not in the good state, ...)"}
      0x29 -> {:target_released_by_initiator, "The PN532 configured as target has been released by its initiator"}
      0x2A -> {:card_id_does_not_match, "PN532 and ISO/IEC14443-3B only: the ID of the card does not match, meaning that the expected card has been exchanged with another one."}
      0x2B -> {:card_disappeared, "PN532 and ISO/IEC14443-3B only: the card previously activated has disappeared."}
      0x2C -> {:target_initiator_nfcid3_mismatch, "Mismatch between the NFCID3 initiator and the NFCID3 target in DEP 212/424 kbps passive."}
      0x2D -> {:over_current_event, "An over-current event has been detected"}
      0x2E -> {:dep_nad_missing, "NAD missing in DEP frame"}
      error -> {:unknown_error, "Unknown error: #{inspect error}"}
    end
  end

  def build_command_frame(tfi, command) do
      length = byte_size(command)
      combined_length = length + 1
      lcs = ~~~combined_length + 1
      dsc_checksum = checksum(tfi <> command)
      dsc = ~~~dsc_checksum + 1
      command_frame(<<0x00>>, <<0x00>>, <<0xFF>>, length, combined_length, lcs, tfi, command, dsc, <<0x00>>)
  end

  def command_frame(preamble, startcode1, startcode2, length, combined_length, lcs, tfi, command, dsc, postamble) do
      <<
        preamble::binary-size(1),
        startcode1::binary-size(1),
        startcode2::binary-size(1),
        combined_length::integer-signed,
        lcs::integer-unsigned,
        tfi::binary-size(1),
        command::binary-size(length),
        dsc::integer-unsigned,
        postamble::binary-size(1)
      >>
  end

  def checksum(data), do: checksum(data, 0)
  def checksum(<<head, rest::bitstring>>, acc), do: checksum(rest, head + acc)
  def checksum(<<>>, acc), do: acc

end
