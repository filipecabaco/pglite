defmodule PgliteEx.Protocol.Messages do
  @moduledoc """
  PostgreSQL wire protocol message encoding and decoding.

  This module implements the PostgreSQL frontend/backend message protocol.
  Reference: https://www.postgresql.org/docs/current/protocol-message-formats.html

  This is where you'll implement the protocol message handling,
  similar to what Postgrex does internally.
  """

  # Message type identifiers (backend -> frontend)
  @auth_ok 'R'
  @param_status 'S'
  @ready_for_query 'Z'
  @row_description 'T'
  @data_row 'D'
  @command_complete 'C'
  @error_response 'E'
  @notice_response 'N'

  # Message type identifiers (frontend -> backend)
  @query 'Q'
  @parse 'P'
  @bind 'B'
  @execute 'E'
  @sync 'S'
  @terminate 'X'

  @doc """
  Encode an AuthenticationOk message.

  Sent by server to indicate successful authentication.
  """
  def encode_authentication_ok do
    # R = Authentication, length = 8, type = 0 (OK)
    <<@auth_ok, 8::32, 0::32>>
  end

  @doc """
  Encode a ParameterStatus message.

  Sent by server to inform client about runtime parameters.
  """
  def encode_parameter_status(name, value) do
    name_bytes = name <> <<0>>
    value_bytes = value <> <<0>>
    body = <<name_bytes::binary, value_bytes::binary>>
    length = byte_size(body) + 4

    <<@param_status, length::32, body::binary>>
  end

  @doc """
  Encode a ReadyForQuery message.

  Sent by server to indicate it's ready for a new command.

  Status can be:
  - 'I' - Idle (not in transaction)
  - 'T' - In transaction block
  - 'E' - In failed transaction block
  """
  def encode_ready_for_query(status \\ "I") do
    status_byte =
      case status do
        "I" -> ?I
        "T" -> ?T
        "E" -> ?E
        _ -> ?I
      end

    <<@ready_for_query, 5::32, status_byte>>
  end

  @doc """
  Encode a RowDescription message.

  Describes the structure of query results.
  """
  def encode_row_description(columns) do
    field_count = length(columns)

    fields_binary =
      Enum.map(columns, fn %{name: name, type_oid: oid} ->
        name_bytes = name <> <<0>>
        # table_oid, column_attr, type_oid, type_size, type_mod, format
        <<name_bytes::binary, 0::32, 0::16, oid::32, -1::16, -1::32, 0::16>>
      end)
      |> IO.iodata_to_binary()

    body = <<field_count::16, fields_binary::binary>>
    length = byte_size(body) + 4

    <<@row_description, length::32, body::binary>>
  end

  @doc """
  Encode a DataRow message.

  Contains the actual data for a single row.
  """
  def encode_data_row(values) do
    column_count = length(values)

    values_binary =
      Enum.map(values, fn
        nil ->
          # NULL value
          <<-1::32>>

        value when is_binary(value) ->
          len = byte_size(value)
          <<len::32, value::binary>>

        value ->
          encoded = encode_value(value)
          len = byte_size(encoded)
          <<len::32, encoded::binary>>
      end)
      |> IO.iodata_to_binary()

    body = <<column_count::16, values_binary::binary>>
    length = byte_size(body) + 4

    <<@data_row, length::32, body::binary>>
  end

  @doc """
  Encode a CommandComplete message.

  Sent after a SQL command completes successfully.
  """
  def encode_command_complete(tag) do
    tag_bytes = tag <> <<0>>
    length = byte_size(tag_bytes) + 4

    <<@command_complete, length::32, tag_bytes::binary>>
  end

  @doc """
  Encode an ErrorResponse message.
  """
  def encode_error_response(message, severity \\ "ERROR", code \\ "42000") do
    severity_field = "S" <> severity <> <<0>>
    code_field = "C" <> code <> <<0>>
    message_field = "M" <> message <> <<0>>

    body = <<severity_field::binary, code_field::binary, message_field::binary, 0>>
    length = byte_size(body) + 4

    <<@error_response, length::32, body::binary>>
  end

  @doc """
  Parse a startup message from client.
  """
  def parse_startup_message(<<length::32, rest::binary>>) do
    payload_length = length - 4
    <<payload::binary-size(payload_length), remaining::binary>> = rest

    <<_version::32, params::binary>> = payload
    params_map = parse_params(params)

    {:startup, params_map, remaining}
  end

  @doc """
  Parse a Query message from client.
  """
  def parse_query(<<@query, length::32, rest::binary>>) do
    payload_length = length - 4
    <<payload::binary-size(payload_length), remaining::binary>> = rest

    # Remove null terminator
    sql = String.trim_trailing(payload, <<0>>)

    {:query, sql, remaining}
  end

  # Helper Functions

  defp parse_params(<<0>>), do: %{}
  defp parse_params(<<>>), do: %{}

  defp parse_params(params) do
    params
    |> String.split(<<0>>)
    |> Enum.reject(&(&1 == ""))
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [key, value] -> {key, value}
      [key] -> {key, ""}
    end)
    |> Map.new()
  end

  defp encode_value(value) when is_integer(value) do
    Integer.to_string(value)
  end

  defp encode_value(value) when is_float(value) do
    Float.to_string(value)
  end

  defp encode_value(value) when is_boolean(value) do
    if value, do: "t", else: "f"
  end

  defp encode_value(value) do
    to_string(value)
  end
end
