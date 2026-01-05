# PGliteEx Implementation Guide

This guide walks through completing the PGliteEx implementation to get PGlite WASM working from Elixir.

## Current Status

✅ **Completed:**
- Project structure and build configuration
- Basic GenServer architecture
- PostgreSQL wire protocol message encoding/decoding (stub)
- Socket server and connection handler
- Documentation and tests

⏳ **To Do:**
- Wasmex integration with proper Emscripten imports
- WASM ↔ Elixir memory bridge
- Callback mechanism for read/write operations
- Full protocol message handling

## Implementation Steps

### Step 1: Get PGlite WASM Files

First, you need the compiled PGlite WASM module:

```bash
cd priv/pglite

# Option A: Download from NPM
npm pack @electric-sql/pglite
tar -xzf electric-sql-pglite-*.tgz
cp package/dist/pglite.wasm ./
cp package/dist/pglite.data ./
rm -rf package *.tgz

# Option B: Build from source (from pglite root)
cd ../../..
pnpm wasm:build
cp packages/pglite/release/pglite.wasm elixir-pglite-bridge/priv/pglite/
cp packages/pglite/release/pglite.data elixir-pglite-bridge/priv/pglite/
```

### Step 2: Implement Emscripten Imports

PGlite WASM expects Emscripten runtime functions. Add to `lib/pglite_ex/bridge/emscripten.ex`:

```elixir
defmodule PgliteEx.Bridge.Emscripten do
  @moduledoc """
  Emscripten runtime function implementations.

  PGlite WASM is compiled with Emscripten and expects certain runtime
  functions to be available. This module provides minimal implementations.
  """

  def build_imports(_store) do
    %{
      "env" => %{
        # Console output
        "__syscall_write" => syscall_write(),

        # Time
        "emscripten_get_now" => get_now(),
        "clock_gettime" => clock_gettime(),

        # Memory (if needed)
        "emscripten_resize_heap" => resize_heap(),

        # Stubs for threading (return errors)
        "pthread_create" => stub_error(),
      },

      "wasi_snapshot_preview1" => %{
        "fd_write" => fd_write(),
        "fd_read" => fd_read(),
        "fd_close" => fd_close(),
        "environ_get" => environ_get(),
        "environ_sizes_get" => environ_sizes_get(),
        # ... other WASI functions
      }
    }
  end

  defp syscall_write do
    {:fn, [:i32, :i32, :i32], [:i32], fn _context, [fd, _buf, count] ->
      # fd=1 is stdout, fd=2 is stderr
      # For now, just return success
      if fd in [1, 2], do: count, else: -1
    end}
  end

  defp get_now do
    {:fn, [], [:f64], fn _context, _args ->
      System.monotonic_time(:millisecond) / 1.0
    end}
  end

  # ... implement other functions
end
```

### Step 3: Implement WASM Memory Bridge

The key challenge is bridging Elixir and WASM memory. Update `lib/pglite_ex/bridge/bridge.ex`:

```elixir
defp setup_wasm_instance(bytes, debug) do
  # Create store
  {:ok, store} = Wasmex.Store.new()

  # Build imports
  imports = Emscripten.build_imports(store)

  # Compile module
  {:ok, module} = Wasmex.Module.compile(store, bytes)

  # Create instance
  {:ok, instance} = Wasmex.Instance.from_module(module, imports)

  # Get memory
  {:ok, memory} = Wasmex.Memory.from_instance(instance)

  {instance, store, memory}
end
```

### Step 4: Implement Callbacks

This is the tricky part. PGlite expects to call back into the host for I/O.

**Challenge:** Wasmex doesn't have Emscripten's `addFunction()`.

**Solutions:**

#### Option A: Function Table Export (Recommended)

Modify PGlite build to export function table, then use it:

```elixir
# Get function table from WASM
{:ok, table} = Wasmex.Table.from_instance(instance, "table_name")

# Create callback wrapper
def wasm_write_callback(ptr, length) do
  # This runs in Elixir
  # Read from WASM memory and process
end

# Add to table
Wasmex.Table.set(table, index, callback)
```

#### Option B: Direct Memory Polling

Simpler but less efficient:

```elixir
def exec_protocol_raw(message, state) do
  # 1. Write message to output buffer
  Wasmex.Memory.write_binary(memory, output_ptr, message)

  # 2. Set buffer metadata (length, offset)
  Wasmex.Memory.write_binary(memory, metadata_ptr,
    <<byte_size(message)::32, 0::32>>)

  # 3. Call WASM function
  {:ok, _} = Wasmex.call_function(instance, "_interactive_one",
    [byte_size(message), first_byte(message)])

  # 4. Read response from input buffer
  {:ok, <<length::32, offset::32>>} =
    Wasmex.Memory.read_binary(memory, response_metadata_ptr, 8)

  {:ok, response} =
    Wasmex.Memory.read_binary(memory, input_ptr + offset, length)

  {:ok, response}
end
```

### Step 5: Initialize Database

Once memory bridge works, initialize Postgres:

```elixir
defp init_database(instance) do
  Logger.info("Initializing PostgreSQL...")

  # Call _pgl_initdb()
  case Wasmex.call_function(instance, "_pgl_initdb", []) do
    {:ok, [1]} ->
      Logger.info("Database initialized")

      # Start backend
      {:ok, _} = Wasmex.call_function(instance, "_pgl_backend", [])
      Logger.info("Backend started")
      :ok

    {:ok, [0]} ->
      {:error, "Database initialization failed"}

    {:error, reason} ->
      {:error, reason}
  end
end
```

### Step 6: Protocol Message Handling

Implement full protocol in `lib/pglite_ex/socket/connection_handler.ex`:

```elixir
def handle_info({:tcp, socket, data}, state) do
  case parse_message(data) do
    {:startup, params} ->
      handle_startup(socket, params, state)

    {:query, sql} ->
      handle_query(socket, sql, state)

    # ... other message types
  end
end

defp handle_startup(socket, _params, state) do
  # Send authentication OK
  :gen_tcp.send(socket, Messages.encode_authentication_ok())

  # Send parameter status
  :gen_tcp.send(socket,
    Messages.encode_parameter_status("server_version", "16.0"))

  # Send ready for query
  :gen_tcp.send(socket, Messages.encode_ready_for_query("I"))

  {:noreply, %{state | state: :ready}}
end
```

## Testing Strategy

### 1. Unit Tests

Test each component in isolation:

```elixir
# test/pglite_ex/bridge_test.exs
test "loads WASM module" do
  assert {:ok, _pid} = Bridge.start_link(wasm_path: "priv/pglite/pglite.wasm")
end

test "executes protocol message" do
  message = build_test_message()
  assert {:ok, response} = Bridge.exec_protocol_raw(message)
end
```

### 2. Integration Tests

Test with real PostgreSQL clients:

```elixir
# test/integration/postgrex_test.exs
test "connects with Postgrex" do
  {:ok, pid} = Postgrex.start_link(
    hostname: "localhost",
    port: 5433,
    database: "postgres"
  )

  result = Postgrex.query!(pid, "SELECT 1", [])
  assert result.rows == [[1]]
end
```

### 3. Manual Testing

```bash
# Start the server
iex -S mix

# In another terminal, connect with psql
PGSSLMODE=disable psql -h localhost -p 5432 -d postgres
```

## Debugging Tips

### 1. Enable Verbose Logging

```elixir
# config/dev.exs
config :pglite_ex, debug: 3
```

### 2. Inspect WASM Memory

```elixir
# In IEx
{:ok, memory} = Wasmex.Memory.from_instance(instance)
{:ok, data} = Wasmex.Memory.read_binary(memory, address, length)
IO.inspect(data, limit: :infinity)
```

### 3. Compare with TypeScript Implementation

Run the TypeScript version side-by-side and compare:

```javascript
// Node.js
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
db.query('SELECT 1').then(console.log);
```

### 4. Use Wireshark

Capture PostgreSQL protocol traffic:

```bash
# Capture on loopback
wireshark -i lo -f "tcp port 5432"
```

## Next Steps After Basic Implementation

1. **Performance Optimization**
   - Pool WASM instances
   - Optimize memory copies
   - Cache compiled modules

2. **Advanced Features**
   - Prepared statements
   - COPY operations
   - LISTEN/NOTIFY
   - Transactions

3. **Extension Support**
   - Load PGlite extensions (pgvector, etc.)
   - Custom type handlers

4. **Production Ready**
   - Error handling
   - Graceful shutdown
   - Resource cleanup
   - Monitoring/metrics

## References

- [PGlite TypeScript Source](https://github.com/electric-sql/pglite/tree/main/packages/pglite/src)
- [PostgreSQL Wire Protocol](https://www.postgresql.org/docs/current/protocol.html)
- [Wasmex Documentation](https://hexdocs.pm/wasmex/)
- [Emscripten Documentation](https://emscripten.org/docs/)
- [Postgrex Source](https://github.com/elixir-ecto/postgrex) - Reference for protocol implementation

## Getting Help

If you get stuck:

1. Check the PGlite TypeScript implementation for reference
2. Review Wasmex examples and tests
3. Ask in the Elixir Forum or Discord
4. Open an issue on the PGlite repo

Good luck! 🚀
