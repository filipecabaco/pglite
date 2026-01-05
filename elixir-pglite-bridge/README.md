# PGliteEx

Elixir bridge to [PGlite](https://pglite.dev) - PostgreSQL compiled to WebAssembly, enabling you to run a full Postgres database in your Elixir application via Wasmex.

## Overview

This project provides:
- **PGlite WASM Bridge**: Run PGlite's WebAssembly module from Elixir using Wasmex
- **PostgreSQL Wire Protocol Server**: TCP socket server that exposes PGlite over the standard PostgreSQL protocol
- **Postgrex Compatibility**: Connect to PGlite using standard Elixir PostgreSQL clients like Postgrex

## Architecture

```
┌─────────────────────┐
│  Postgrex Client    │  (or any PostgreSQL client)
└──────────┬──────────┘
           │ PostgreSQL Wire Protocol
           ▼
┌─────────────────────┐
│  PgliteEx.Socket    │  Socket server (GenServer)
│  Server             │  Handles TCP connections
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  PgliteEx.Bridge    │  WASM bridge (GenServer)
│                     │  Manages PGlite instance
└──────────┬──────────┘
           │ Memory & Function Calls
           ▼
┌─────────────────────┐
│  PGlite WASM        │  Full PostgreSQL in WASM
│  (via Wasmex)       │
└─────────────────────┘
```

## Installation

### Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25 or later
- Rust (required by Wasmex)

### Setup

1. Clone the repository:
```bash
git clone https://github.com/electric-sql/pglite
cd pglite/elixir-pglite-bridge
```

2. Install dependencies:
```bash
mix deps.get
```

3. Download PGlite WASM files:
```bash
# Option A: Download from NPM
cd priv/pglite
npm pack @electric-sql/pglite
tar -xzf electric-sql-pglite-*.tgz
cp package/dist/pglite.wasm ./
cp package/dist/pglite.data ./
rm -rf package electric-sql-pglite-*.tgz

# Option B: Build from source (from pglite root)
cd ../..
pnpm wasm:build
cp packages/pglite/release/pglite.wasm elixir-pglite-bridge/priv/pglite/
cp packages/pglite/release/pglite.data elixir-pglite-bridge/priv/pglite/
```

## Usage

### Start the Socket Server

```elixir
# Start the application
iex -S mix

# The socket server will start automatically on port 5432
# You can configure it in config/config.exs
```

### Connect with Postgrex

```elixir
# Start a Postgrex connection
{:ok, pid} = Postgrex.start_link(
  hostname: "localhost",
  port: 5432,
  database: "postgres",
  username: "postgres",
  password: "postgres"
)

# Execute queries
Postgrex.query!(pid, "SELECT 1 as num", [])
# => %Postgrex.Result{rows: [[1]], ...}

# Create tables
Postgrex.query!(pid, """
  CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
  )
""", [])

# Insert data
Postgrex.query!(pid, "INSERT INTO users (name, email) VALUES ($1, $2)",
  ["Alice", "alice@example.com"])

# Query data
Postgrex.query!(pid, "SELECT * FROM users WHERE name = $1", ["Alice"])
```

### Connect with psql

```bash
# From command line (disable SSL as PGlite doesn't support it)
PGSSLMODE=disable psql -h localhost -p 5432 -d postgres

# Now you can run SQL commands
postgres=# SELECT version();
postgres=# CREATE TABLE test (id int, name text);
postgres=# INSERT INTO test VALUES (1, 'Hello from PGlite!');
postgres=# SELECT * FROM test;
```

## Configuration

Edit `config/config.exs`:

```elixir
config :pglite_ex,
  # Path to PGlite WASM file
  wasm_path: "priv/pglite/pglite.wasm",

  # Socket server configuration
  socket_port: 5432,
  socket_host: "127.0.0.1",

  # Debug level (0-5)
  debug: 0,

  # Initial WASM memory (in bytes)
  initial_memory: 256 * 1024 * 1024  # 256MB
```

## Development Status

This is an early prototype demonstrating the feasibility of running PGlite from Elixir.

### What Works
- [x] Basic project structure
- [x] WASM module loading via Wasmex
- [ ] Memory bridge between Elixir and WASM
- [ ] PostgreSQL wire protocol implementation
- [ ] Query execution
- [ ] Transaction support
- [ ] Connection pooling

### Known Limitations

1. **Single Connection**: Like PGlite itself, only one connection at a time is supported
2. **Callback Functions**: Wasmex doesn't have direct equivalent of Emscripten's `addFunction()` - requires custom solution
3. **Emscripten Runtime**: PGlite WASM expects Emscripten runtime functions - need to implement stubs

## How It Works

PGlite TypeScript implementation uses callbacks to bridge JavaScript ↔ WASM:

```typescript
// TypeScript (from packages/pglite/src/pglite.ts)
this.#pglite_write = this.mod.addFunction((ptr, length) => {
  const bytes = this.mod.HEAPU8.subarray(ptr, ptr + length)
  // Process PostgreSQL wire protocol data
}, 'iii')

this.mod._set_read_write_cbs(this.#pglite_read, this.#pglite_write)
this.mod._interactive_one(message.length, message[0])
```

Our Elixir implementation replicates this:

```elixir
# Elixir (from lib/pglite_ex/bridge.ex)
def exec_protocol_raw(message) do
  # 1. Write message to WASM memory
  :ok = Wasmex.Memory.write_binary(memory, output_ptr, message)

  # 2. Call WASM function
  {:ok, [length]} = Wasmex.call_function(instance, "_interactive_one",
    [byte_size(message), first_byte])

  # 3. Read response from WASM memory
  {:ok, response} = Wasmex.Memory.read_binary(memory, input_ptr, length)
end
```

## Testing

```bash
# Run tests
mix test

# Run with coverage
mix test --cover

# Type checking
mix dialyzer
```

## Roadmap

- [ ] Implement full Emscripten runtime stubs
- [ ] Complete PostgreSQL wire protocol implementation
- [ ] Add proper callback mechanism for WASM ↔ Elixir communication
- [ ] Support for PGlite extensions (pgvector, etc.)
- [ ] Connection pooling and queue management
- [ ] Performance benchmarks vs native Postgres
- [ ] Docker image for easy deployment

## Contributing

Contributions welcome! This is an experimental project to demonstrate Elixir + WASM + Postgres.

## Related Projects

- [PGlite](https://pglite.dev) - PostgreSQL in WASM
- [Wasmex](https://github.com/tessi/wasmex) - WebAssembly runtime for Elixir
- [Postgrex](https://github.com/elixir-ecto/postgrex) - PostgreSQL driver for Elixir

## License

Apache 2.0 (same as PGlite)
