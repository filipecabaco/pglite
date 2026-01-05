# PGlite Go Port

Go-based port that runs PGlite WASM using Wazero runtime.

## Architecture

This is a standalone Go binary that:
1. Loads PGlite WASM using Wazero
2. Configures filesystem mounting for persistence (memory or file-based)
3. Initializes PostgreSQL database
4. Reads PostgreSQL wire protocol messages from stdin
5. Executes them against PGlite WASM
6. Writes responses to stdout
7. Communicates with Elixir via Erlang Port

## Why Go + Wazero?

- ✅ **Built-in WASI support** - Works with PGlite out of the box
- ✅ **Filesystem mounting** - FSConfig for persistent storage
- ✅ **Single binary** - Easy deployment, no dependencies
- ✅ **Low memory** - ~20MB per instance
- ✅ **Good performance** - Sufficient for database workloads
- ✅ **Cross-platform** - Linux, macOS, FreeBSD support

## Build

The build is automated by the Elixir Mix compiler. For manual builds:

```bash
# Install dependencies
go mod download

# Build
go build -o pglite-port main.go

# Or with optimizations (recommended)
go build -ldflags="-s -w" -trimpath -o pglite-port main.go
```

## Configuration via Environment Variables

The port reads configuration from environment variables:

- `PGLITE_WASM_PATH` - Path to PGlite WASM file (default: `../priv/pglite/pglite.wasm`)
- `PGLITE_DATA_DIR` - Data directory (default: `memory://`)
  - `memory://` - In-memory (ephemeral)
  - `./path` or `file://path` - File-based persistence
- `PGLITE_USERNAME` - PostgreSQL username (default: `postgres`)
- `PGLITE_DATABASE` - Database name (default: `postgres`)
- `PGLITE_DEBUG` - Debug level 0-5 (default: `0`)

## Run Standalone (for testing)

```bash
# Set configuration
export PGLITE_WASM_PATH=../priv/pglite/pglite.wasm
export PGLITE_DATA_DIR=memory://
export PGLITE_DEBUG=1

# Run
./pglite-port

# Test with echo
echo "Q\x00\x00\x00\x0dSELECT 1\x00" | ./pglite-port
```

## Protocol

### Input (stdin)
- PostgreSQL wire protocol messages
- Newline-delimited
- Binary format

### Output (stdout)
- Length-prefixed responses
- Format: `<4 bytes length (big-endian)><response data>`

### Logging (stderr)
- Debug and error messages
- Controlled by `PGLITE_DEBUG` level

## Integration with Elixir

The Elixir side spawns this port and communicates via stdin/stdout:

```elixir
# In PgliteEx.Bridge.PortBridge
def init(opts) do
  port = Port.open({:spawn_executable, "priv/pglite-port"}, [
    :binary,
    :exit_status,
    {:packet, 4},  # 4-byte length prefix
    {:env, [
      {~c"PGLITE_WASM_PATH", wasm_path},
      {~c"PGLITE_DATA_DIR", data_dir}
    ]}
  ])

  {:ok, %{port: port}}
end
```

## How It Works (Maps to PGlite TypeScript)

| TypeScript | Go |
|------------|-----|
| `new PGlite()` | `NewPGliteInstance()` |
| `execProtocolRawSync()` | `ExecProtocolRaw()` |
| `mod._pgl_initdb()` | `initDatabase()` → `_pgl_initdb()` |
| `mod._interactive_one()` | `_interactive_one.Call()` |
| `#outputData` | `instance.outputData` |
| `#inputData` | `instance.inputData` |

## Memory Management

Each `PGliteInstance`:
- 1MB input buffer
- Dynamic output buffer
- WASM module memory (~20MB for PGlite)
- **Total: ~21MB per instance**

For multiple instances:
- Each instance is fully isolated
- No shared memory between instances
- Scales linearly with instance count

## Filesystem Persistence

Uses Wazero's `FSConfig` for mounting host directories:

```go
// For file-based persistence
moduleConfig.WithFSConfig(
  wazero.NewFSConfig().WithDirMount(hostPath, "/pgdata")
)
```

This mounts the host directory into the WASM filesystem at `/pgdata`, enabling:
- Data persistence across restarts
- Standard file I/O operations
- Portable database files

## Error Handling

Errors are logged to stderr and sent to Elixir as:
```
ERROR: <error message>
```

Elixir pattern matches on `<<"ERROR:", _::binary>>` to handle errors.

## Cross-Platform Builds

Use `build_release.sh` to create binaries for all supported platforms:

```bash
./build_release.sh
```

Creates binaries in `bin/`:
- `linux-amd64/pglite-port`
- `linux-arm64/pglite-port`
- `darwin-amd64/pglite-port`
- `darwin-arm64/pglite-port`

## Development

```bash
# Format code
go fmt ./...

# Build and test
go build -o pglite-port main.go
echo "SELECT 1" | ./pglite-port
```

## Deployment

Deployment is automatic via the Mix compiler:

1. User adds PGliteEx as dependency
2. Mix compiler detects platform
3. Uses pre-built binary from `bin/` if available
4. Falls back to building from source if Go is installed
5. Binary copied to `_build/*/lib/pglite_ex/priv/`

No manual deployment steps required!

## Further Reading

- [PACKAGING.md](../PACKAGING.md) - Distribution strategy
- [ARCHITECTURE.md](../ARCHITECTURE.md) - System architecture
- [Wazero Documentation](https://wazero.io/) - WASM runtime details
