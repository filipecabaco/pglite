defmodule PgliteEx.Bridge.PortBridge do
  @moduledoc """
  Bridge to PGlite WASM via Go port.

  This module manages communication with the pglite-port Go binary,
  which runs PGlite WASM using the Wazero runtime.

  The port handles:
  - Loading and initializing PGlite WASM
  - Executing PostgreSQL wire protocol messages
  - Managing WASM memory and callbacks

  This is a complete replacement for the Wasmex-based bridge.
  """

  use GenServer
  require Logger

  defstruct [:port, :pending_calls, :debug]

  # Client API

  @doc """
  Start the port bridge GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a PostgreSQL wire protocol message.

  ## Parameters
    - message: Binary containing the PostgreSQL wire protocol message

  ## Returns
    - `{:ok, response}` - The response from PGlite as a binary
    - `{:error, reason}` - If the query fails

  ## Examples

      iex> message = build_query_message("SELECT 1")
      iex> PgliteEx.Bridge.PortBridge.exec_protocol_raw(message)
      {:ok, <<...>>}
  """
  @spec exec_protocol_raw(binary()) :: {:ok, binary()} | {:error, term()}
  def exec_protocol_raw(message) when is_binary(message) do
    GenServer.call(__MODULE__, {:exec_protocol_raw, message}, :infinity)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    debug = Keyword.get(opts, :debug, 0)
    port_path = Keyword.get(opts, :port_path, find_port_executable())

    Logger.info("Initializing PGlite port bridge...")
    Logger.debug("Port executable: #{port_path}")

    # Check if port executable exists
    unless File.exists?(port_path) do
      Logger.error("Port executable not found at: #{port_path}")
      Logger.error("Please build the Go port: cd pglite_port && make install")
      {:stop, {:error, :port_executable_not_found}}
    else
      # Check if WASM file exists
      wasm_path = Keyword.get(opts, :wasm_path, "priv/pglite/pglite.wasm")

      unless File.exists?(wasm_path) do
        Logger.error("WASM file not found at: #{wasm_path}")
        Logger.error("Please download PGlite WASM files - see README.md")
        {:stop, {:error, :wasm_file_not_found}}
      else
        # Start the port
        port_opts = [
          :binary,
          :exit_status,
          {:packet, 4},
          # 4-byte length prefix
          {:env,
           [
             {~c"PGLITE_WASM_PATH", String.to_charlist(Path.expand(wasm_path))}
           ]}
        ]

        port = Port.open({:spawn_executable, String.to_charlist(port_path)}, port_opts)

        # Monitor port for crashes
        Port.monitor(port)

        state = %__MODULE__{
          port: port,
          pending_calls: %{},
          debug: debug
        }

        Logger.info("PGlite port bridge started successfully")
        {:ok, state}
      end
    end
  end

  @impl true
  def handle_call({:exec_protocol_raw, message}, from, state) do
    if state.debug > 0 do
      Logger.debug("Sending #{byte_size(message)} bytes to port")

      if state.debug > 1 do
        log_hex_dump(message, "→ outgoing to port")
      end
    end

    # Send message to port
    try do
      Port.command(state.port, message)

      # Store the caller to reply when we get response
      call_id = make_ref()
      new_pending = Map.put(state.pending_calls, call_id, from)

      {:noreply, %{state | pending_calls: new_pending}}
    rescue
      e ->
        Logger.error("Error sending to port: #{inspect(e)}")
        {:reply, {:error, :port_send_failed}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    if state.debug > 0 do
      Logger.debug("Received #{byte_size(data)} bytes from port")

      if state.debug > 1 do
        log_hex_dump(data, "← incoming from port")
      end
    end

    # Check if it's an error response
    case data do
      <<"ERROR:", error_msg::binary>> ->
        Logger.error("Port returned error: #{error_msg}")
        reply_to_oldest_caller({:error, error_msg}, state)

      response ->
        # Reply to oldest pending caller
        reply_to_oldest_caller({:ok, response}, state)
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("Port crashed: #{inspect(reason)}")
    {:stop, {:port_crashed, reason}, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Port exited with status: #{status}")
    {:stop, {:port_exited, status}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Port bridge terminating: #{inspect(reason)}")

    if state.port do
      Port.close(state.port)
    end

    :ok
  end

  # Private Functions

  defp reply_to_oldest_caller(reply, state) do
    case Enum.min(Map.keys(state.pending_calls), fn -> nil end) do
      nil ->
        Logger.warning("Received response but no pending callers")
        {:noreply, state}

      call_id ->
        from = Map.get(state.pending_calls, call_id)
        GenServer.reply(from, reply)
        new_pending = Map.delete(state.pending_calls, call_id)
        {:noreply, %{state | pending_calls: new_pending}}
    end
  end

  defp find_port_executable do
    # Look for port executable in various locations
    candidates = [
      "priv/pglite-port",
      Path.join([Application.app_dir(:pglite_ex, "priv"), "pglite-port"]),
      "pglite_port/pglite-port"
    ]

    Enum.find(candidates, fn path ->
      File.exists?(path)
    end) || "priv/pglite-port"
  end

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
