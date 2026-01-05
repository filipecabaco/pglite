defmodule PgliteEx.SocketServer do
  @moduledoc """
  TCP server that exposes PGlite over PostgreSQL wire protocol.

  Similar to packages/pglite-socket/src/index.ts from the TypeScript implementation.

  This server:
  - Listens on a TCP port (default 5432)
  - Accepts PostgreSQL client connections
  - Forwards wire protocol messages to PGlite WASM bridge
  - Returns responses to clients
  """

  use GenServer
  require Logger

  defstruct [:listen_socket, :port, :host, :debug]

  # Client API

  @doc """
  Start the socket server.

  ## Options
    - `:port` - TCP port to listen on (default: 5432)
    - `:host` - Host to bind to (default: "127.0.0.1")
    - `:debug` - Debug level 0-5 (default: 0)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 5432)
    host = Keyword.get(opts, :host, "127.0.0.1")
    debug = Keyword.get(opts, :debug, 0)

    Logger.info("Starting PGlite socket server...")

    # Parse IP address
    listen_opts = [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      ip: parse_ip(host)
    ]

    case :gen_tcp.listen(port, listen_opts) do
      {:ok, listen_socket} ->
        Logger.info("PGlite socket server listening on #{host}:#{port}")
        Logger.info("Connect with: PGSSLMODE=disable psql -h #{host} -p #{port} -d postgres")

        # Start acceptor process
        spawn_link(fn -> accept_loop(listen_socket, debug) end)

        {:ok,
         %__MODULE__{
           listen_socket: listen_socket,
           port: port,
           host: host,
           debug: debug
         }}

      {:error, reason} ->
        Logger.error("Failed to start socket server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Stopping PGlite socket server: #{inspect(reason)}")

    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  # Private Functions

  defp accept_loop(listen_socket, debug) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Get client info
        {:ok, {address, port}} = :inet.peername(client_socket)
        client_info = "#{:inet.ntoa(address)}:#{port}"

        Logger.info("Client connected: #{client_info}")

        # Spawn connection handler
        {:ok, _pid} =
          PgliteEx.ConnectionHandler.start_link(
            socket: client_socket,
            client_info: client_info,
            debug: debug
          )

        # Continue accepting
        accept_loop(listen_socket, debug)

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        :timer.sleep(100)
        accept_loop(listen_socket, debug)
    end
  end

  defp parse_ip(ip) when is_binary(ip) do
    ip
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, addr} -> addr
      {:error, _} -> {127, 0, 0, 1}
    end
  end

  defp parse_ip(ip) when is_list(ip), do: parse_ip(to_string(ip))
  defp parse_ip({_, _, _, _} = ip), do: ip
end
