# PGliteEx Examples

This directory contains example scripts demonstrating how to use PGliteEx.

## Prerequisites

Before running the examples, ensure you have:

1. **Elixir installed** (1.14 or later)
2. **Go installed** (1.19 or later)
3. **Built the Go port:**
   ```bash
   cd pglite_port
   make install
   ```
4. **Downloaded PGlite WASM files** to `priv/pglite/`
5. **Installed dependencies:**
   ```bash
   mix deps.get
   ```

## Examples

### 1. Simple Query Example

**File:** `simple_query.exs`

The simplest way to get started with PGliteEx. Demonstrates:
- Single-instance mode (default)
- Basic SQL queries (CREATE, INSERT, SELECT)
- Transactions
- JSON/JSONB support
- Connecting with Postgrex

**Run:**
```bash
mix run examples/simple_query.exs
```

**Expected Output:**
```
=== Simple PGliteEx Query Example ===

Starting PGlite on port 5432...
✓ PGlite instance ready!

Connecting to PostgreSQL...
✓ Connected!

Example 1: Check PostgreSQL Version
========================================
PostgreSQL Version: PostgreSQL 16.0 (PGlite)

Example 2: Create a Table
========================================
✓ Table 'users' created
...
```

### 2. Multi-Instance Demo

**File:** `multi_instance_demo.exs`

Advanced example showing multiple isolated database instances. Demonstrates:
- Multi-instance mode
- Ephemeral (in-memory) databases
- Persistent (file-based) databases
- Running multiple instances simultaneously
- Instance management API (start, stop, list, info)

**Run:**
```bash
mix run examples/multi_instance_demo.exs
```

**Expected Output:**
```
=== PGliteEx Multi-Instance Demo ===

Demo 1: Ephemeral In-Memory Database
==================================================
Starting ephemeral database on port 5432...
✓ Instance started: :ephemeral_db
  Connect with: psql -h localhost -p 5432 -U postgres -d postgres
...
```

## Example Patterns

### Single Instance Mode

```elixir
# Configure in config/config.exs
config :pglite_ex,
  socket_port: 5432,
  socket_host: "127.0.0.1",
  data_dir: "memory://"

# Start the application
{:ok, _} = Application.ensure_all_started(:pglite_ex)

# Connect with any PostgreSQL client
{:ok, conn} = Postgrex.start_link(
  hostname: "localhost",
  port: 5432,
  username: "postgres",
  database: "postgres"
)

# Run queries
{:ok, result} = Postgrex.query(conn, "SELECT 1", [])
```

### Multi-Instance Mode

```elixir
# Configure in config/config.exs
config :pglite_ex,
  multi_instance: true

# Start the application
{:ok, _} = Application.ensure_all_started(:pglite_ex)

# Start instances dynamically
{:ok, _} = PgliteEx.start_instance(:prod_db,
  port: 5433,
  data_dir: "./data/production"
)

{:ok, _} = PgliteEx.start_instance(:dev_db,
  port: 5434,
  data_dir: "memory://"
)

# List running instances
[:prod_db, :dev_db] = PgliteEx.list_instances()

# Get instance info
{:ok, info} = PgliteEx.instance_info(:prod_db)

# Stop an instance
:ok = PgliteEx.stop_instance(:dev_db)
```

### Persistence Modes

```elixir
# In-memory (ephemeral) - data lost on restart
PgliteEx.start_instance(:temp_db,
  port: 5432,
  data_dir: "memory://"
)

# File-based (persistent) - data survives restarts
PgliteEx.start_instance(:prod_db,
  port: 5433,
  data_dir: "./data/production"
)

# With file:// prefix
PgliteEx.start_instance(:backup_db,
  port: 5434,
  data_dir: "file:///var/lib/pglite/backup"
)
```

## Connecting with Standard Tools

Since PGliteEx implements the PostgreSQL wire protocol, you can connect with standard PostgreSQL tools:

### psql

```bash
psql -h localhost -p 5432 -U postgres -d postgres
```

### pgAdmin, DBeaver, TablePlus

Use these connection settings:
- **Host:** localhost
- **Port:** 5432 (or your configured port)
- **Username:** postgres
- **Password:** (leave blank, uses trust auth)
- **Database:** postgres

### Ecto (Phoenix Framework)

```elixir
# config/dev.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "",
  hostname: "localhost",
  port: 5432,
  database: "postgres",
  pool_size: 10
```

## Common Use Cases

### Testing

Use in-memory mode for fast, isolated tests:

```elixir
# test_helper.exs
Application.put_env(:pglite_ex, :socket_port, 5432)
Application.put_env(:pglite_ex, :data_dir, "memory://")
{:ok, _} = Application.ensure_all_started(:pglite_ex)
```

### Development

Use persistent mode to keep data between restarts:

```elixir
# config/dev.exs
config :pglite_ex,
  socket_port: 5432,
  data_dir: "./dev_data"
```

### Multi-Tenant Applications

Run isolated databases per tenant:

```elixir
tenants = [:tenant_a, :tenant_b, :tenant_c]

Enum.each(tenants, fn tenant ->
  PgliteEx.start_instance(tenant,
    port: 5432 + tenant_id(tenant),
    data_dir: "./data/#{tenant}"
  )
end)
```

## Troubleshooting

### Port executable not found

```
** (EXIT from #PID<...>) {:error, :port_executable_not_found}
```

**Solution:** Build the Go port:
```bash
cd pglite_port && make install
```

### WASM file not found

```
** (EXIT from #PID<...>) {:error, :wasm_file_not_found}
```

**Solution:** Download PGlite WASM files to `priv/pglite/`

### Port already in use

```
** (EXIT from #PID<...>) {:error, :eaddrinuse}
```

**Solution:** Use a different port or stop the conflicting process:
```bash
lsof -i :5432
kill -9 <PID>
```

### Connection refused

```
** (DBConnection.ConnectionError) tcp connect (localhost:5432): connection refused
```

**Solution:** Wait a moment for the instance to start, or check logs for errors:
```elixir
# Give the instance time to start
Process.sleep(1000)
```

## Performance Tips

1. **Use in-memory mode for tests** - Much faster than disk I/O
2. **Adjust pool size** - Postgrex can handle multiple concurrent connections
3. **Use prepared statements** - Faster query execution
4. **Enable debug mode** - Use `debug: 1` to see query logs during development

## Further Reading

- [PGliteEx Architecture](../ARCHITECTURE.md)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)
- [Postgrex Documentation](https://hexdocs.pm/postgrex/)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
