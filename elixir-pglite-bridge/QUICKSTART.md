# Quick Start Guide

Get PGliteEx running in 5 minutes!

## Prerequisites

- **Elixir 1.14+** and **Erlang/OTP 25+**
- **Go 1.22+** (for building the WASM runtime port)
- **npm** (for downloading PGlite WASM files)

## Installation

### 1. Clone and Setup

```bash
git clone https://github.com/electric-sql/pglite
cd pglite/elixir-pglite-bridge

# One command to rule them all
make setup
```

This will:
- Download PGlite WASM files from NPM
- Build the Go port binary
- Set up the project

### 2. Install Elixir Dependencies

```bash
mix deps.get
```

### 3. Build

```bash
make build
```

### 4. Run

```bash
make run
# or
iex -S mix
```

You should see:
```
[info] Starting PgliteEx application...
[info] PGlite port bridge started successfully
[info] PGlite socket server listening on 127.0.0.1:5432
[info] Connect with: PGSSLMODE=disable psql -h 127.0.0.1 -p 5432 -d postgres
```

## Test It!

### Option 1: Using psql

```bash
# In another terminal
PGSSLMODE=disable psql -h localhost -p 5432 -d postgres

# Now you can run SQL!
postgres=# SELECT 1;
postgres=# CREATE TABLE test (id int, name text);
postgres=# INSERT INTO test VALUES (1, 'Hello from PGlite!');
postgres=# SELECT * FROM test;
```

### Option 2: Using Postgrex (Elixir)

```elixir
# In iex
{:ok, pid} = Postgrex.start_link(
  hostname: "localhost",
  port: 5432,
  database: "postgres"
)

Postgrex.query!(pid, "SELECT 1", [])
# => %Postgrex.Result{rows: [[1]], ...}
```

## Project Structure

```
elixir-pglite-bridge/
├── lib/
│   └── pglite_ex/
│       ├── bridge/
│       │   └── port_bridge.ex    # Elixir ↔ Go port communication
│       └── socket/
│           ├── server.ex          # TCP server
│           └── connection_handler.ex
├── pglite_port/                   # Go WASM runtime
│   ├── main.go                    # Port implementation
│   └── Makefile
├── priv/
│   ├── pglite/                    # WASM files
│   │   ├── pglite.wasm
│   │   └── pglite.data
│   └── pglite-port                # Go binary
└── Makefile                       # Build commands
```

## How It Works

```
PostgreSQL Client (psql/Postgrex)
          ↓
    TCP Socket (5432)
          ↓
PgliteEx.SocketServer (Elixir)
          ↓
  PgliteEx.PortBridge (Elixir)
          ↓  Port (stdin/stdout)
  pglite-port (Go binary)
          ↓  Wazero runtime
    PGlite WASM (PostgreSQL)
```

## Troubleshooting

### "Port executable not found"

Build the Go port:
```bash
cd pglite_port
make install
```

### "WASM file not found"

Download WASM files:
```bash
make download-wasm
```

### "Connection refused"

Check if the server is running:
```elixir
# In iex
PgliteEx.ready?()
# Should return: true
```

### Port crashes immediately

Check logs and WASM path:
```bash
# Set debug level
# In config/dev.exs
config :pglite_ex, debug: 2

# Restart
make run
```

## Next Steps

- Read the full [README.md](README.md)
- Check [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) for architecture
- Review [WASM_RUNTIME_COMPARISON.md](WASM_RUNTIME_COMPARISON.md) for runtime choice
- Explore [pglite_port/README.md](pglite_port/README.md) for Go port details

## Common Commands

```bash
# Build everything
make build

# Run tests
make test

# Clean and rebuild
make clean
make build

# Just rebuild Go port
make build-go

# Format code
make fmt
```

## Performance Tips

For production:
1. Set `debug: 0` in `config/prod.exs`
2. Build Go port with optimizations (already done in Makefile)
3. Consider connection pooling for multiple clients
4. Monitor memory usage with `:observer.start()`

## Help

If you get stuck:
1. Check the logs (`debug: 2` in config)
2. Review the [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)
3. Open an issue on GitHub

Happy hacking! 🚀
