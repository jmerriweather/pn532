defmodule Pn532Test do
  use ExUnit.Case, async: false

  @test_uart "COM4"

  setup_all do
    # start mifare client genserver
    start_result = PN532.Supervisor.start_link([%{target_type: :iso_14443_type_a}])

    #open uart
    #open_result = PN532.Client.open(@test_uart)

    # on_exit fn ->
    #   MifareClientTest.close(pid)
    # end

    {:ok, [start_result: start_result]}
  end

  # test "open PN532 mifare client", %{start_result: {result, _}} do
  #   assert result == :ok
  # end

  test "get PN532 firmware version", state do
    {:ok, firmware_version} = PN532.Client.get_firmware_version()
    #IO.puts(inspect(firmware_version))
    assert firmware_version == %{ic_version: "2", revision: 6, support: 7, version: 1}
  end

  test "start and stop mifare target detection", state do
    start_result = PN532.Client.start_target_detection()
    Process.sleep(500)
    stop_result = PN532.Client.stop_target_detection()

    assert start_result == :ok
    assert stop_result == :ok
  end
end
