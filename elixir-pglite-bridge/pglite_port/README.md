# PGlite Go Port

Go-based port that runs PGlite WASM using Wazero runtime.

## Architecture

This is a standalone Go binary that:
1. Loads PGlite WASM using Wazero
2. Initializes PostgreSQL database
3. Reads PostgreSQL wire protocol messages from stdin
4. Executes them against PGlite WASM
5. Writes responses to stdout
6. Communicates with Elixir via Port

## Why Go + Wazero?

- ✅ **Built-in Emscripten support** - Works with PGlite out of the box
- ✅ **Single binary** - Easy deployment, no dependencies
- ✅ **Low memory** - ~20MB per instance
- ✅ **Good performance** - Sufficient for database workloads
- ✅ **Simple concurrency** - Goroutines for multiple connections

See ../WASM_RUNTIME_COMPARISON.md for detailed analysis.

## Build

```bash
# Install dependencies
go mod download

# Build
go build -o pglite-port main.go

# Or with optimizations
go build -ldflags="-s -w" -o pglite-port main.go
```

## Run Standalone (for testing)

```bash
# Set WASM path (optional, defaults to ../priv/pglite/pglite.wasm)
export PGLITE_WASM_PATH=../priv/pglite/pglite.wasm

# Run
./pglite-port

# Test with echo
echo "Q\x00\x00\x00\x0dSELECT 1\x00" | ./pglite-port
```

## Protocol

### Input (stdin)
- PostgreSQL wire protocol messages
- One message per line
- Binary format

### Output (stdout)
- Length-prefixed responses
- Format: `<4 bytes length (big-endian)><response data>`

### Logging (stderr)
- Debug and error messages
- Safe to ignore in production

## Integration with Elixir

The Elixir side spawns this port and communicates via stdin/stdout:

```elixir
# In PgliteEx.Bridge
def init(opts) do
  port = Port.open({:spawn_executable, "priv/pglite-port"}, [
    :binary,
    :exit_status,
    packet: 4  # 4-byte length prefix
  ])

  {:ok, %{port: port}}
end

def handle_call({:exec_protocol_raw, message}, _from, state) do
  Port.command(state.port, message)

  receive do
    {port, {:data, response}} ->
      {:reply, {:ok, response}, state}
  after
    5000 -> {:reply, {:error, :timeout}, state}
  end
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
- Allocates 1MB input buffer
- Dynamically sized output buffer
- WASM module memory (~20MB for PGlite)
- **Total: ~21MB per instance**

For 100 concurrent connections:
- 100 instances × 21MB = ~2.1GB
- With instance pooling: Much less!

## Error Handling

Errors are logged to stderr and sent to Elixir as:
```
ERROR: <error message>
```

Elixir can pattern match on `<<"ERROR:", _::binary>>` to handle errors.

## TODO

- [ ] Implement callback mechanism for `_set_read_write_cbs`
- [ ] Add connection pooling (reuse instances)
- [ ] Implement graceful shutdown
- [ ] Add metrics/monitoring
- [ ] Optimize buffer sizes based on load
- [ ] Add configuration via environment variables

## Development

```bash
# Run tests (once implemented)
go test ./...

# Format code
go fmt ./...

# Lint
golangci-lint run
```

## Deployment

Copy `pglite-port` binary to `priv/` in your Elixir app:

```bash
# Build
cd pglite_port
go build -ldflags="-s -w" -o pglite-port main.go

# Copy to Elixir priv
cp pglite-port ../priv/

# Make executable
chmod +x ../priv/pglite-port
```

The Elixir app will find it at runtime.
