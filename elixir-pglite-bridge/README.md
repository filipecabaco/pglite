# PGliteEx

**PostgreSQL in WebAssembly for Elixir** - Run a full Postgres database in your Elixir application with zero external dependencies.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)

PGliteEx is an Elixir bridge to [PGlite](https://pglite.dev), bringing PostgreSQL compiled to WebAssembly to the BEAM. Connect using standard PostgreSQL clients like Postgrex, psql, or any tool that speaks the PostgreSQL wire protocol.

## ✨ Features

- **🚀 Zero-Setup Installation** - Just add as a dependency and run `mix deps.get`
- **🗄️ Full PostgreSQL** - Real Postgres 16 with transactions, indexes, and constraints
- **🔌 Standard Protocol** - Works with Postgrex, psql, pgAdmin, DBeaver, etc.
- **💾 Persistent or Ephemeral** - Choose in-memory or file-based storage
- **🏢 Multi-Instance** - Run multiple isolated databases simultaneously
- **⚡ Lightning Fast** - Compiled WASM with minimal overhead
- **🔒 Isolated** - Each instance runs in its own WASM sandbox

## 📦 Installation

### As a Git Dependency

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:pglite_ex, github: "your-org/pglite-elixir-bridge"},
    {:postgrex, "~> 0.17"}  # For connecting to PGlite
  ]
end
```

**That's it!** Run `mix deps.get` and everything is set up automatically:

```bash
mix deps.get   # Downloads repo, builds/downloads dependencies
iex -S mix     # Start using PGlite immediately!
```

The first compile will:
1. ✓ Detect your platform (Linux, macOS, etc.)
2. ✓ Download PGlite WASM files from CDN
3. ✓ Use pre-built Go binary for your platform (or build from source if Go is installed)
4. ✓ Ready to use - no manual steps!

### Supported Platforms

Pre-built binaries included for:
- **Linux x86_64** (Ubuntu, Debian, RHEL, etc.)
- **Linux ARM64** (Raspberry Pi 4+, AWS Graviton, etc.)
- **macOS Intel** (Older Macs)
- **macOS Apple Silicon** (M1/M2/M3 Macs)

Other Unix platforms can build from source (requires Go 1.19+).

## 🚀 Quick Start

### Single Instance Mode (Default)

The simplest way to use PGliteEx - one database, zero configuration:

```elixir
# config/config.exs
config :pglite_ex,
  socket_port: 5432,
  data_dir: "memory://"  # Ephemeral - data lost on restart

# Start your application
iex -S mix
```

**Connect with Postgrex:**

```elixir
{:ok, conn} = Postgrex.start_link(
  hostname: "localhost",
  port: 5432,
  username: "postgres",
  database: "postgres"
)

Postgrex.query!(conn, "SELECT version()", [])
# => %Postgrex.Result{rows: [["PostgreSQL 16.0 (PGlite)"]], ...}

Postgrex.query!(conn, "CREATE TABLE users (id SERIAL, name TEXT)", [])
Postgrex.query!(conn, "INSERT INTO users (name) VALUES ($1)", ["Alice"])
```

**Or use psql:**

```bash
psql -h localhost -p 5432 -U postgres -d postgres
```

### Multi-Instance Mode

Run multiple isolated databases with different configurations:

```elixir
# config/config.exs
config :pglite_ex,
  multi_instance: true

# In your application or IEx
{:ok, _} = PgliteEx.start_instance(:prod_db,
  port: 5433,
  data_dir: "./data/production"  # Persistent storage
)

{:ok, _} = PgliteEx.start_instance(:test_db,
  port: 5434,
  data_dir: "memory://"  # Ephemeral for tests
)

# List all instances
PgliteEx.list_instances()
# => [:prod_db, :test_db]

# Stop an instance
PgliteEx.stop_instance(:test_db)
```

## 💾 Storage Modes

### In-Memory (Ephemeral)

Perfect for tests, temporary data, or when persistence isn't needed:

```elixir
config :pglite_ex,
  data_dir: "memory://"
```

- ⚡ **Fast**: No disk I/O
- 🗑️ **Ephemeral**: Data lost on restart
- 🧪 **Ideal for**: Tests, caches, temporary workloads

### File-Based (Persistent)

Data survives restarts and system reboots:

```elixir
config :pglite_ex,
  data_dir: "./data/mydb"  # or "file://./data/mydb"
```

- 💾 **Persistent**: Data survives restarts
- 📁 **Portable**: Copy directory to move database
- 🏢 **Ideal for**: Production, development, backups

## 🎯 Use Cases

### Testing

Fast, isolated databases for each test:

```elixir
# test_helper.exs
Application.put_env(:pglite_ex, :data_dir, "memory://")
{:ok, _} = Application.ensure_all_started(:pglite_ex)

# In tests - instant database, no cleanup needed!
```

### Development

Consistent database across team without Docker:

```elixir
# config/dev.exs
config :pglite_ex,
  socket_port: 5432,
  data_dir: "./dev_data"  # Git-ignored, persistent
```

### Embedded Applications

Ship your app with database included:

```bash
# No PostgreSQL installation needed!
./my_app
```

### Multi-Tenant Applications

Isolated database per tenant:

```elixir
Enum.each(tenants, fn tenant_id ->
  PgliteEx.start_instance(:"tenant_#{tenant_id}",
    port: 5432 + tenant_id,
    data_dir: "./data/tenant_#{tenant_id}"
  )
end)
```

## 📖 Examples

See the [`examples/`](examples/) directory for complete working examples:

- **[simple_query.exs](examples/simple_query.exs)** - Basic usage, SQL queries, transactions
- **[multi_instance_demo.exs](examples/multi_instance_demo.exs)** - Advanced multi-instance patterns

Run them with:

```bash
mix run examples/simple_query.exs
mix run examples/multi_instance_demo.exs
```

## 🏗️ Architecture

```
┌─────────────────────┐
│  PostgreSQL Client  │  (Postgrex, psql, pgAdmin, etc.)
└──────────┬──────────┘
           │ PostgreSQL Wire Protocol (TCP)
           ▼
┌─────────────────────┐
│  SocketServer       │  Elixir GenServer
│  (Elixir)           │  Accepts connections
└──────────┬──────────┘
           │ Binary messages
           ▼
┌─────────────────────┐
│  PortBridge         │  Elixir GenServer
│  (Elixir)           │  Manages Go port
└──────────┬──────────┘
           │ Erlang Port (stdin/stdout)
           ▼
┌─────────────────────┐
│  pglite-port        │  Go binary
│  (Go + Wazero)      │  WASM runtime
└──────────┬──────────┘
           │ WASM function calls
           ▼
┌─────────────────────┐
│  PGlite WASM        │  PostgreSQL 16 in WASM
│  (WebAssembly)      │  Full SQL database
└─────────────────────┘
```

## 📚 Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Detailed system architecture
- **[TESTING.md](TESTING.md)** - Testing guide and strategies
- **[PACKAGING.md](PACKAGING.md)** - How distribution and packaging works
- **[examples/README.md](examples/README.md)** - Example applications guide

## 🧪 Testing

```bash
# Run unit tests (fast, no dependencies)
mix test

# Run integration tests (requires built system)
mix test --include integration

# With coverage
mix test --cover
```

See [TESTING.md](TESTING.md) for comprehensive testing guide.

## ⚙️ Configuration

```elixir
config :pglite_ex,
  # Single vs multi-instance mode
  multi_instance: false,  # Set to true for multi-instance

  # Single-instance configuration
  socket_port: 5432,
  socket_host: "127.0.0.1",
  data_dir: "memory://",  # "memory://" or file path
  username: "postgres",
  database: "postgres",
  debug: 0,  # 0-5, higher = more verbose
  wasm_path: "priv/pglite/pglite.wasm"
```

For multi-instance mode, configure each instance at runtime:

```elixir
PgliteEx.start_instance(:my_db,
  port: 5432,
  host: "127.0.0.1",
  data_dir: "./data/mydb",
  username: "admin",
  database: "myapp",
  debug: 1
)
```

## 🔧 Advanced Usage

### Instance Management API

```elixir
# Start instance
{:ok, pid} = PgliteEx.start_instance(:my_db, port: 5432, data_dir: "./data")

# Get info
{:ok, info} = PgliteEx.instance_info(:my_db)
# => %{name: :my_db, pid: #PID<...>, running: true}

# List all instances
[:db1, :db2] = PgliteEx.list_instances()

# Stop instance
:ok = PgliteEx.stop_instance(:my_db)
```

### With Ecto

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "",
  hostname: "localhost",
  port: 5432,
  database: "postgres",
  pool_size: 10
```

Then use Ecto normally - PGliteEx speaks standard PostgreSQL protocol!

## 🚀 Performance

PGlite performs surprisingly well for many workloads:

- **Simple queries**: ~1ms
- **Bulk inserts**: ~100k rows/sec
- **Memory usage**: ~50MB base + data size
- **Startup time**: ~200ms

See [benchmarks](benchmarks/) for detailed comparisons.

## 🤝 Contributing

Contributions are welcome! This is an experimental project exploring Elixir + WASM + PostgreSQL.

Areas we'd love help with:
- Windows support
- Additional platform binaries
- Performance optimization
- Documentation improvements
- Example applications

## 🐛 Troubleshooting

### Port executable not found

**Solution**: The library will auto-build from source if Go is installed. Otherwise:

```bash
cd pglite_port
make install
```

### WASM download failed

**Solution**: Download manually:

```bash
mkdir -p priv/pglite
curl -L -o priv/pglite/pglite.wasm \
  https://cdn.jsdelivr.net/npm/@electric-sql/pglite@0.1.5/dist/postgres.wasm
```

### Port already in use

**Solution**: Use a different port:

```elixir
config :pglite_ex, socket_port: 5433
```

See [PACKAGING.md](PACKAGING.md#troubleshooting) for more solutions.

## 📋 Requirements

- **Elixir**: 1.14 or later
- **Erlang/OTP**: 25 or later
- **Go** (optional): 1.19+ for building from source

No other dependencies! No PostgreSQL installation needed.

## 🗺️ Roadmap

- [x] Core PostgreSQL wire protocol
- [x] Multi-instance support
- [x] File-based persistence
- [x] Zero-setup packaging
- [ ] Windows support
- [ ] Hex.pm publishing
- [ ] Performance optimizations
- [ ] PGlite extensions support (pgvector, etc.)
- [ ] Replication/backup utilities
- [ ] Metrics and monitoring

## 📜 License

Apache 2.0 (same as PGlite)

## 🙏 Acknowledgments

- [PGlite](https://pglite.dev) - PostgreSQL in WebAssembly
- [Wazero](https://wazero.io/) - Zero-dependency WebAssembly runtime for Go
- [Postgrex](https://github.com/elixir-ecto/postgrex) - PostgreSQL driver for Elixir

## 🔗 Related Projects

- [PGlite](https://github.com/electric-sql/pglite) - PostgreSQL in WASM (TypeScript)
- [Postgrex](https://github.com/elixir-ecto/postgrex) - PostgreSQL driver for Elixir
- [Wazero](https://github.com/tetratelabs/wazero) - WebAssembly runtime in Go
- [Ecto](https://github.com/elixir-ecto/ecto) - Database wrapper for Elixir

---

**Made with ❤️ for the Elixir community**
