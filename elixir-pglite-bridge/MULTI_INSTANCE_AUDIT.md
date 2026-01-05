# Multi-Instance & Persistence Audit

Audit of current implementation against requirements for multiple PGlite instances and persistence options.

## Requirements

1. ✅ **Multiple PGlite instances** on different ports
2. ✅ **In-memory persistence** (like TypeScript "memory://")
3. ✅ **File persistence** (like TypeScript file paths)
4. ✅ **Configuration** matching TypeScript approach

## Current Implementation Status

### ❌ Issue 1: Single Instance Only

**Current:**
```elixir
# application.ex - Only ONE instance
children = [
  {PgliteEx.Bridge.PortBridge, [wasm_path: wasm_path, debug: debug]},
  {PgliteEx.SocketServer, [port: socket_port, host: socket_host]}
]
```

**Problem:** Can only run one PGlite instance, one port.

**What TypeScript Does:**
```typescript
// Can create multiple instances
const db1 = new PGlite("memory://")
const db2 = new PGlite("./data/db1")
const db3 = new PGlite("idb://mydb")
```

---

### ❌ Issue 2: No dataDir Support

**Current Go Port:**
```go
// main.go - Hardcoded to load WASM, no dataDir
wasmPath := os.Getenv("PGLITE_WASM_PATH")
wasmBytes, _ := os.ReadFile(wasmPath)
```

**Problem:** Doesn't accept or use dataDir configuration.

**What TypeScript Does:**
```typescript
// packages/pglite/src/fs/index.ts
export function parseDataDir(dataDir?: string) {
  if (dataDir?.startsWith('memory://')) {
    fsType = 'memoryfs'  // In-memory only
  } else if (!dataDir) {
    fsType = 'memoryfs'  // Default to memory
  } else {
    fsType = 'nodefs'  // File persistence
  }
  return { dataDir, fsType }
}
```

---

### ❌ Issue 3: No Filesystem Configuration

**Current:** WASM runs with whatever default Emscripten provides.

**What We Need:**
- Memory-only mode (ephemeral, fast)
- File persistence mode (data survives restarts)
- Mount points for data directories

**TypeScript Implementation:**
- `MemoryFS`: All data in WASM memory (lost on restart)
- `NodeFS`: Mount to filesystem (data persists)
- `IdbFS`: IndexedDB in browser (data persists)

For our Go port, we need:
- Memory-only: Don't mount filesystem, keep in WASM
- File persistence: Mount directory to WASM filesystem

---

### ❌ Issue 4: No Multi-Port Support

**Current:** Single socket server on one port.

**What We Need:**
```elixir
# Multiple PGlite instances on different ports
config :pglite_ex,
  instances: [
    db1: [port: 5432, data_dir: "memory://"],
    db2: [port: 5433, data_dir: "./data/db1"],
    db3: [port: 5434, data_dir: "./data/db2"]
  ]
```

---

## Required Changes

### 1. Configuration Schema

**File: `config/config.exs`**
```elixir
config :pglite_ex,
  # Global settings
  wasm_path: "priv/pglite/pglite.wasm",
  debug: 0,

  # Multiple instances
  instances: [
    # Default instance (memory-only, fast)
    default: [
      port: 5432,
      host: "127.0.0.1",
      data_dir: "memory://",  # Ephemeral
      username: "postgres",
      database: "postgres"
    ],

    # Persistent instance
    prod_db: [
      port: 5433,
      host: "127.0.0.1",
      data_dir: "./data/production",  # Persists to disk
      username: "postgres",
      database: "production"
    ],

    # Development instance
    dev_db: [
      port: 5434,
      host: "127.0.0.1",
      data_dir: "./data/development",
      username: "postgres",
      database: "development"
    ]
  ]
```

### 2. Dynamic Supervisor for Instances

**File: `lib/pglite_ex/instance_supervisor.ex`** (NEW)
```elixir
defmodule PgliteEx.InstanceSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_instance(name, config) do
    spec = {PgliteEx.Instance, [name: name, config: config]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_instance(name) do
    # Find and terminate the instance
    children = DynamicSupervisor.which_children(__MODULE__)
    # ... stop logic
  end

  def list_instances do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
```

### 3. Per-Instance Supervisor

**File: `lib/pglite_ex/instance.ex`** (NEW)
```elixir
defmodule PgliteEx.Instance do
  use Supervisor

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    config = Keyword.fetch!(opts, :config)

    port = Keyword.fetch!(config, :port)
    host = Keyword.get(config, :host, "127.0.0.1")
    data_dir = Keyword.get(config, :data_dir, "memory://")
    username = Keyword.get(config, :username, "postgres")
    database = Keyword.get(config, :database, "postgres")
    debug = Keyword.get(config, :debug, 0)

    children = [
      # Each instance gets its own Go port
      {PgliteEx.Bridge.PortBridge,
       [
         name: bridge_name(name),
         wasm_path: Application.get_env(:pglite_ex, :wasm_path),
         data_dir: data_dir,
         username: username,
         database: database,
         debug: debug
       ]},

      # Each instance gets its own socket server
      {PgliteEx.SocketServer,
       [
         name: server_name(name),
         bridge: bridge_name(name),
         port: port,
         host: host,
         debug: debug
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(name), do: {:via, Registry, {PgliteEx.Registry, {:instance, name}}}
  defp bridge_name(name), do: {:via, Registry, {PgliteEx.Registry, {:bridge, name}}}
  defp server_name(name), do: {:via, Registry, {PgliteEx.Registry, {:server, name}}}
end
```

### 4. Update Go Port for dataDir

**File: `pglite_port/main.go`** (MODIFY)
```go
type Config struct {
	WASMPath string
	DataDir  string
	Username string
	Database string
	Debug    int
}

func main() {
	// Read config from environment or stdin
	config := readConfig()

	// Parse dataDir like TypeScript
	fsType := parseDataDir(config.DataDir)

	instance, err := NewPGliteInstance(context.Background(), config, fsType)
	// ...
}

func parseDataDir(dataDir string) string {
	if dataDir == "" || strings.HasPrefix(dataDir, "memory://") {
		return "memoryfs"
	} else {
		return "nodefs"
	}
}

func (inst *PGliteInstance) setupFilesystem(config Config, fsType string) error {
	if fsType == "nodefs" {
		// Mount filesystem for persistence
		dataDir := strings.TrimPrefix(config.DataDir, "file://")

		// Create directory if it doesn't exist
		if err := os.MkdirAll(dataDir, 0755); err != nil {
			return err
		}

		// TODO: Mount to WASM filesystem
		// This requires Wazero filesystem support
		log.Printf("Mounting filesystem at: %s", dataDir)
	} else {
		log.Println("Using in-memory filesystem (ephemeral)")
	}

	return nil
}
```

### 5. Protocol: Config Exchange

**Elixir → Go:**
```elixir
# On port startup, send config as JSON
config_json = Jason.encode!(%{
  data_dir: data_dir,
  username: username,
  database: database,
  debug: debug
})

Port.command(port, config_json <> "\n")
```

**Go receives:**
```go
// First line is config
scanner := bufio.NewScanner(os.Stdin)
scanner.Scan()
configJSON := scanner.Bytes()

var config Config
json.Unmarshal(configJSON, &config)

// Initialize with config
instance, _ := NewPGliteInstance(ctx, config)

// Then process protocol messages
for scanner.Scan() {
	message := scanner.Bytes()
	response := instance.ExecProtocolRaw(message)
	writeResponse(response)
}
```

### 6. Update Application Supervisor

**File: `lib/pglite_ex/application.ex`** (MODIFY)
```elixir
def start(_type, _args) do
  children = [
    # Registry for named instances
    {Registry, keys: :unique, name: PgliteEx.Registry},

    # Dynamic supervisor for instances
    PgliteEx.InstanceSupervisor
  ]

  opts = [strategy: :one_for_one, name: PgliteEx.Supervisor]
  {:ok, sup} = Supervisor.start_link(children, opts)

  # Start configured instances
  instances = Application.get_env(:pglite_ex, :instances, [])

  Enum.each(instances, fn {name, config} ->
    PgliteEx.InstanceSupervisor.start_instance(name, config)
  end)

  {:ok, sup}
end
```

### 7. Public API for Instance Management

**File: `lib/pglite_ex.ex`** (ADD)
```elixir
@doc """
Start a new PGlite instance dynamically.

## Examples

    iex> PgliteEx.start_instance(:my_db, port: 5435, data_dir: "./data/mydb")
    {:ok, pid}

    iex> PgliteEx.start_instance(:temp, port: 5436, data_dir: "memory://")
    {:ok, pid}
"""
def start_instance(name, config) do
  PgliteEx.InstanceSupervisor.start_instance(name, config)
end

@doc """
Stop a running instance.
"""
def stop_instance(name) do
  PgliteEx.InstanceSupervisor.stop_instance(name)
end

@doc """
List all running instances.
"""
def list_instances do
  PgliteEx.InstanceSupervisor.list_instances()
end

@doc """
Get connection info for an instance.

## Examples

    iex> PgliteEx.connection_info(:default)
    %{host: "127.0.0.1", port: 5432, database: "postgres"}
"""
def connection_info(instance_name) do
  # Lookup via Registry
  # Return connection details
end
```

---

## Comparison with TypeScript

| Feature | TypeScript | Our Implementation (After Changes) |
|---------|------------|-------------------------------------|
| Multiple instances | ✅ `new PGlite()` each | ✅ `start_instance/2` |
| In-memory | ✅ `"memory://"` | ✅ `data_dir: "memory://"` |
| File persistence | ✅ `"./path"` | ✅ `data_dir: "./path"` |
| Browser persistence | ✅ `"idb://path"` | ❌ N/A (server-side only) |
| Config-driven | ⚠️ Manual | ✅ `config.exs` + dynamic |
| Connection pooling | ❌ One per instance | ✅ Via Elixir (future) |

---

## Implementation Priority

### Phase 1: Core Multi-Instance (REQUIRED)
1. ✅ Instance supervisor
2. ✅ Per-instance port bridge
3. ✅ Configuration schema
4. ✅ Registry for named instances

### Phase 2: Persistence Support (REQUIRED)
1. ✅ Parse dataDir in Elixir
2. ✅ Pass config to Go port
3. ✅ Go port parses dataDir
4. ⚠️ Mount filesystem in Wazero (complex)

### Phase 3: Nice-to-Have
1. Dynamic instance management API
2. Connection pooling per instance
3. Health checks
4. Metrics/monitoring

---

## Wazero Filesystem Support Challenge

**Problem:** Wazero's filesystem support for mounting host directories is limited.

**Options:**

### Option A: Emscripten FS (Recommended)
Use Emscripten's filesystem API (already in PGlite WASM):
```go
// This requires accessing Emscripten FS API from Wazero
// The WASM module already has FS support built-in
// We just need to call the right functions
```

### Option B: WASI Preview 1 (Limited)
WASI Preview 1 has directory mapping:
```go
import "github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"

config := wazero.NewModuleConfig().
    WithFSConfig(wazero.NewFSConfig().
        WithDirMount(dataDir, "/pgdata"))
```

**Issue:** PGlite expects Emscripten FS, not WASI FS.

### Option C: Hybrid Approach (Pragmatic)
1. In-memory works out of the box (no filesystem needed)
2. For persistence: Pre-populate WASM FS on startup
3. Sync to host filesystem periodically

---

## Recommended Implementation Path

### Immediate (Week 1)
1. ✅ Add multi-instance configuration support
2. ✅ Instance supervisor with Registry
3. ✅ Pass dataDir to Go port
4. ✅ Parse dataDir in Go (memory vs file)
5. ⚠️ Document filesystem limitation

### Short-term (Week 2-3)
1. Implement WASI filesystem mounting (if compatible)
2. Add filesystem sync operations
3. Test with real workloads
4. Performance tuning

### Long-term
1. Investigate Emscripten FS from Wazero
2. Contribute to Wazero if needed
3. Full parity with TypeScript

---

## Testing Strategy

```elixir
# test/multi_instance_test.exs
defmodule MultiInstanceTest do
  use ExUnit.Case

  test "start multiple instances on different ports" do
    {:ok, _} = PgliteEx.start_instance(:db1, port: 9001, data_dir: "memory://")
    {:ok, _} = PgliteEx.start_instance(:db2, port: 9002, data_dir: "memory://")

    # Connect to both
    {:ok, conn1} = Postgrex.start_link(port: 9001)
    {:ok, conn2} = Postgrex.start_link(port: 9002)

    # Data is isolated
    Postgrex.query!(conn1, "CREATE TABLE test (id int)", [])
    assert_raise _, fn ->
      Postgrex.query!(conn2, "SELECT * FROM test", [])
    end
  end

  test "memory instance is ephemeral" do
    {:ok, pid} = PgliteEx.start_instance(:temp, port: 9003, data_dir: "memory://")
    {:ok, conn} = Postgrex.start_link(port: 9003)

    Postgrex.query!(conn, "CREATE TABLE test (id int)", [])
    Postgrex.query!(conn, "INSERT INTO test VALUES (1)", [])

    # Stop and restart
    PgliteEx.stop_instance(:temp)
    {:ok, _} = PgliteEx.start_instance(:temp, port: 9003, data_dir: "memory://")
    {:ok, conn2} = Postgrex.start_link(port: 9003)

    # Data is gone
    assert_raise _, fn ->
      Postgrex.query!(conn2, "SELECT * FROM test", [])
    end
  end

  test "file instance persists data" do
    data_dir = "/tmp/pglite_test_#{:rand.uniform(1000)}"

    {:ok, _} = PgliteEx.start_instance(:persist, port: 9004, data_dir: data_dir)
    {:ok, conn} = Postgrex.start_link(port: 9004)

    Postgrex.query!(conn, "CREATE TABLE test (id int)", [])
    Postgrex.query!(conn, "INSERT INTO test VALUES (42)", [])

    # Stop and restart with same data_dir
    PgliteEx.stop_instance(:persist)
    {:ok, _} = PgliteEx.start_instance(:persist, port: 9004, data_dir: data_dir)
    {:ok, conn2} = Postgrex.start_link(port: 9004)

    # Data is still there
    result = Postgrex.query!(conn2, "SELECT * FROM test", [])
    assert result.rows == [[42]]
  end
end
```

---

## Summary

**Current Status:** ❌ Single instance only, no persistence control

**Required Changes:**
1. Multi-instance supervisor architecture
2. dataDir configuration support
3. Go port config protocol
4. Filesystem mounting (challenging)

**Complexity:** Medium-High (filesystem mounting is tricky)

**Recommendation:** Implement multi-instance first (easy), defer full filesystem support until Wazero improves or we find workaround.

**See:** Next file `MULTI_INSTANCE_IMPLEMENTATION.md` for step-by-step guide.
