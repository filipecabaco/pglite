defmodule PgliteEx.Protocol.MessagesTest do
  use ExUnit.Case
  alias PgliteEx.Protocol.Messages

  describe "encode_authentication_ok/0" do
    test "produces correct message" do
      message = Messages.encode_authentication_ok()
      # R + length(8) + auth_type(0)
      assert <<~c"R", 8::32, 0::32>> = message
    end
  end

  describe "encode_parameter_status/2" do
    test "encodes parameter status message" do
      message = Messages.encode_parameter_status("server_version", "16.0")
      assert <<~c"S", _length::32, rest::binary>> = message
      assert String.contains?(rest, "server_version")
      assert String.contains?(rest, "16.0")
    end
  end

  describe "encode_ready_for_query/1" do
    test "encodes idle status" do
      message = Messages.encode_ready_for_query("I")
      assert <<~c"Z", 5::32, ?I>> = message
    end

    test "encodes transaction status" do
      message = Messages.encode_ready_for_query("T")
      assert <<~c"Z", 5::32, ?T>> = message
    end
  end

  describe "encode_command_complete/1" do
    test "encodes command completion" do
      message = Messages.encode_command_complete("SELECT 1")
      assert <<~c"C", _length::32, "SELECT 1", 0>> = message
    end
  end

  describe "encode_error_response/3" do
    test "encodes error message" do
      message = Messages.encode_error_response("syntax error")
      assert <<~c"E", _length::32, rest::binary>> = message
      assert String.contains?(rest, "syntax error")
    end
  end
end
