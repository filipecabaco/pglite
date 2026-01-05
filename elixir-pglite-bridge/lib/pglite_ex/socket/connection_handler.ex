defmodule PgliteEx.ConnectionHandler do
  @moduledoc """
  Handles a single PostgreSQL wire protocol connection.

  Similar to PGLiteSocketHandler in TypeScript (packages/pglite-socket/src/index.ts).

  This GenServer:
  - Receives raw TCP data from a PostgreSQL client
  - Forwards it to PGlite bridge as wire protocol messages
  - Sends responses back to the client
  """

  use GenServer
  require Logger

  alias PgliteEx.Bridge

  defstruct [:socket, :client_info, :debug, :state]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    client_info = Keyword.get(opts, :client_info, "unknown")
    debug = Keyword.get(opts, :debug, 0)

    # Transfer socket control to this process
    :ok = :gen_tcp.controlling_process(socket, self())

    # Set socket to active mode to receive messages
    :inet.setopts(socket, active: :once)

    Logger.info("Connection handler started for: #{client_info}")

    {:ok,
     %__MODULE__{
       socket: socket,
       client_info: client_info,
       debug: debug,
       state: :startup
     }}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    if state.debug > 1 do
      Logger.debug("Received #{byte_size(data)} bytes from #{state.client_info}")
      log_hex_dump(data, "incoming")
    end

    # Forward raw protocol data to PGlite bridge
    case Bridge.exec_protocol_raw(data) do
      {:ok, response} when byte_size(response) > 0 ->
        if state.debug > 1 do
          Logger.debug("Sending #{byte_size(response)} bytes to #{state.client_info}")
          log_hex_dump(response, "outgoing")
        end

        :gen_tcp.send(socket, response)

      {:ok, _empty} ->
        if state.debug > 0 do
          Logger.debug("Empty response from PGlite (this is normal during startup)")
        end

      {:error, reason} ->
        Logger.error("Error executing protocol: #{inspect(reason)}")
        # Send error response to client
        # TODO: Format as PostgreSQL ErrorResponse message
    end

    # Continue receiving
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Client disconnected: #{state.client_info}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("TCP error for #{state.client_info}: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  # Private Functions

  defp log_hex_dump(data, direction) do
    IO.puts(String.duplicate("-", 75))
    IO.puts("#{direction} #{byte_size(data)} bytes")

    # Process 16 bytes per line
    data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, index} ->
      offset = index * 16

      # Hex representation
      hex =
        chunk
        |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
        |> Enum.join(" ")
        |> String.pad_trailing(47, " ")

      # ASCII representation
      ascii =
        chunk
        |> Enum.map(fn byte ->
          if byte >= 32 and byte <= 126, do: <<byte>>, else: "."
        end)
        |> Enum.join()

      # Print line
      offset_str = offset |> Integer.to_string(16) |> String.pad_leading(8, "0")
      IO.puts("#{offset_str}  #{hex} #{ascii}")
    end)
  end
end
