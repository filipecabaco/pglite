# PGliteEx Architecture

This document describes the architecture of the Elixir PGlite bridge, including component responsibilities, data flow, and design decisions.

## Overview

PGliteEx provides an Elixir/Erlang interface to PGlite (PostgreSQL WASM), enabling PostgreSQL databases running entirely in WebAssembly to be accessed via standard PostgreSQL wire protocol.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     PostgreSQL Client                        │
│                 (psql, pgAdmin, Ecto, etc.)                  │
└────────────────────────────┬────────────────────────────────┘
                             │ PostgreSQL Wire Protocol (TCP)
                             │
┌────────────────────────────▼────────────────────────────────┐
│              PgliteEx.SocketServer (Elixir)                  │
│           Accepts connections, handles auth                  │
└────────────────────────────┬────────────────────────────────┘
                             │ Binary Messages
                             │
┌────────────────────────────▼────────────────────────────────┐
│            PgliteEx.Bridge.PortBridge (Elixir)               │
│        GenServer managing communication with Go port         │
└────────────────────────────┬────────────────────────────────┘
                             │ Erlang Port (stdin/stdout)
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  Go Port (pglite-port)                       │
│         Manages Wazero runtime and WASM instance             │
└────────────────────────────┬────────────────────────────────┘
                             │ WASM Function Calls
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  PGlite WASM Module                          │
│              PostgreSQL 16 compiled to WASM                  │
│            (from @electric-sql/pglite package)               │
└─────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. PgliteEx (Public API)

**Module:** `PgliteEx`

**Responsibilities:**
- Public API for instance management
- Start/stop instances dynamically
- Query instance information
- Facade over internal modules

**Key Functions:**
- `start_instance/2` - Start a named instance with configuration
- `stop_instance/1` - Stop a running instance
- `list_instances/0` - List all active instances
- `instance_info/1` - Get details about an instance

### 2. Application Supervisor

**Module:** `PgliteEx.Application`

**Responsibilities:**
- Application startup and configuration
- Choose between single-instance and multi-instance mode
- Build appropriate supervision tree

**Modes:**

#### Single-Instance Mode (Default)
```
PgliteEx.Supervisor
├── Registry (PgliteEx.Registry)
└── PgliteEx.Instance (:default)
    ├── PgliteEx.Bridge.PortBridge
    └── PgliteEx.SocketServer
```

- Starts one instance automatically on app startup
- Backward compatible with simple use cases
- Instance named `:default`

#### Multi-Instance Mode
```
PgliteEx.Supervisor
├── Registry (PgliteEx.Registry)
└── PgliteEx.InstanceSupervisor (DynamicSupervisor)
    ├── PgliteEx.Instance (:instance1)
    │   ├── PgliteEx.Bridge.PortBridge
    │   └── PgliteEx.SocketServer
    ├── PgliteEx.Instance (:instance2)
    │   ├── PgliteEx.Bridge.PortBridge
    │   └── PgliteEx.SocketServer
    └── ...
```

- Infrastructure only (Registry + DynamicSupervisor)
- Instances started/stopped via API
- Full isolation between instances

### 3. Instance Supervisor

**Module:** `PgliteEx.Instance`

**Responsibilities:**
- Supervise a single PGlite instance
- Manage two child processes (Bridge + SocketServer)
- Handle instance-specific configuration
- Register processes in Registry for name lookup

**Configuration:**
- `name` - Unique atom identifier
- `port` - TCP port for PostgreSQL connections
- `host` - Bind address (default: 127.0.0.1)
- `data_dir` - Data storage location (memory:// or file path)
- `username` - Database username (default: postgres)
- `database` - Database name (default: postgres)
- `debug` - Debug level 0-5 (default: 0)
- `wasm_path` - Path to PGlite WASM file

### 4. Instance Supervisor Manager

**Module:** `PgliteEx.InstanceSupervisor`

**Type:** `DynamicSupervisor`

**Responsibilities:**
- Manage multiple instances dynamically
- Start/stop child instance supervisors
- Track running instances via Registry
- Prevent duplicate instance names

### 5. Port Bridge

**Module:** `PgliteEx.Bridge.PortBridge`

**Type:** `GenServer`

**Responsibilities:**
- Manage Erlang Port to Go process
- Send PostgreSQL wire protocol messages to Go
- Receive responses from Go
- Handle port crashes and restart

**Communication Protocol:**
- Messages use 4-byte length prefix (big-endian)
- Binary PostgreSQL wire protocol messages
- Synchronous request-response model
- Queue pending callers during processing

### 6. Socket Server

**Module:** `PgliteEx.SocketServer`

**Type:** `GenServer` with Ranch acceptor pool

**Responsibilities:**
- Listen on TCP port
- Accept PostgreSQL client connections
- Spawn connection handlers
- Forward queries to PortBridge

### 7. Connection Handler

**Module:** `PgliteEx.SocketConnectionHandler`

**Responsibilities:**
- Handle individual client connection
- Implement PostgreSQL wire protocol handshake
- Authentication (trust mode)
- Forward queries and results

### 8. Go Port (pglite-port)

**Language:** Go

**Responsibilities:**
- Load and initialize PGlite WASM
- Manage Wazero runtime
- Execute WASM function calls
- Handle filesystem mounting for persistence
- Read from stdin, write to stdout

**Key Functions:**
- `main()` - Main event loop reading from stdin
- `NewPGliteInstance()` - Initialize WASM runtime
- `configureFilesystem()` - Mount host directories
- `ExecProtocolRaw()` - Execute PostgreSQL messages

### 9. Registry

**Module:** `PgliteEx.Registry`

**Type:** Elixir `Registry`

**Responsibilities:**
- Name lookup for instances
- Unique process registration
- Enable dynamic instance discovery

**Registry Keys:**
- `{:instance, name}` - Instance supervisor
- `{:bridge, name}` - Port bridge for instance
- `{:server, name}` - Socket server for instance

## Data Flow

### Query Execution Flow

1. **Client Connection**
   ```
   PostgreSQL Client → SocketServer (TCP :5432)
   ```

2. **Authentication**
   ```
   SocketServer → ConnectionHandler
   ConnectionHandler → Client (AuthenticationOk)
   ```

3. **Query**
   ```
   Client → "SELECT 1"
   ConnectionHandler → Encode wire protocol message
   ConnectionHandler → PortBridge.exec_protocol_raw(message)
   ```

4. **Bridge to Port**
   ```
   PortBridge → Port.command(message)
   Port → Go process stdin
   ```

5. **Go Processing**
   ```
   Go reads stdin → Parse message
   Go → Call WASM function (_interactive_one)
   WASM → Execute SQL, generate response
   WASM → Return binary response
   Go → Write to stdout (with 4-byte length prefix)
   ```

6. **Response Back**
   ```
   Go stdout → Elixir Port
   PortBridge → Receive {:data, response}
   PortBridge → GenServer.reply(from, {:ok, response})
   ConnectionHandler → Receive response
   ConnectionHandler → Send to client socket
   Client → Receive result rows
   ```

## Persistence Modes

### In-Memory (Ephemeral)

**Configuration:** `data_dir: "memory://"`

**Behavior:**
- All data stored in WASM linear memory
- Data lost on process restart
- Fast, no disk I/O
- Suitable for testing, temporary data

### File-Based (Persistent)

**Configuration:** `data_dir: "./data/mydb"` or `data_dir: "file://data/mydb"`

**Behavior:**
- Host directory mounted to WASM at `/pgdata`
- Uses Wazero's `FSConfig.WithDirMount()`
- PostgreSQL files written to real filesystem
- Data survives restarts
- Suitable for production

**Implementation:**
```go
moduleConfig.WithFSConfig(
    wazero.NewFSConfig().WithDirMount(absPath, "/pgdata")
)
```

## Process Hierarchy

### Single Instance
```
PgliteEx.Supervisor (Supervisor)
├── Registry (keys: unique)
└── PgliteEx.Instance (Supervisor, name: :default)
    ├── PgliteEx.Bridge.PortBridge (GenServer)
    │   └── [Port to Go process]
    └── PgliteEx.SocketServer (GenServer)
        └── [Ranch acceptor pool]
            └── [Connection handlers (Tasks)]
```

### Multiple Instances
```
PgliteEx.Supervisor (Supervisor)
├── Registry (keys: unique)
└── PgliteEx.InstanceSupervisor (DynamicSupervisor)
    ├── PgliteEx.Instance (name: :db1)
    │   ├── PgliteEx.Bridge.PortBridge
    │   └── PgliteEx.SocketServer (port: 5433)
    ├── PgliteEx.Instance (name: :db2)
    │   ├── PgliteEx.Bridge.PortBridge
    │   └── PgliteEx.SocketServer (port: 5434)
    └── ...
```

## Design Decisions

### Why Go Port Instead of NIFs?

**Chosen:** Erlang Port with Go

**Alternatives Considered:**
- Wasmex (Elixir NIF wrapper)
- Direct Rust NIF

**Rationale:**
1. **Isolation:** Port crashes don't crash BEAM VM
2. **WASM Runtime:** Wazero is mature, fast, and has excellent filesystem support
3. **Simplicity:** Avoid NIF complexity and safety concerns
4. **Performance:** Port communication overhead minimal for query workloads

### Why Registry Instead of Named Processes?

**Chosen:** Elixir Registry with compound keys

**Rationale:**
1. **Dynamic Discovery:** List instances at runtime
2. **Unique Names:** Prevent duplicate instances
3. **Flexible Keys:** `{:bridge, name}` pattern enables clean lookup
4. **Standard:** Idiomatic Elixir approach

### Why Two Modes (Single/Multi)?

**Rationale:**
1. **Backward Compatibility:** Single mode works out of the box
2. **Simplicity:** Most users need one database
3. **Flexibility:** Multi-instance for advanced use cases
4. **Resource Efficiency:** Don't start DynamicSupervisor unless needed

## Configuration Reference

### Application Config (config.exs)

```elixir
# Single-instance mode (default)
config :pglite_ex,
  socket_port: 5432,
  socket_host: "127.0.0.1",
  data_dir: "memory://",
  username: "postgres",
  database: "postgres",
  debug: 0,
  wasm_path: "priv/pglite/pglite.wasm"

# Multi-instance mode
config :pglite_ex,
  multi_instance: true
```

### Runtime Instance Config

```elixir
PgliteEx.start_instance(:my_db,
  port: 5433,
  host: "127.0.0.1",
  data_dir: "./data/production",
  username: "admin",
  database: "myapp",
  debug: 1
)
```

## Error Handling

### Port Crashes
- PortBridge monitors port
- On crash: PortBridge terminates
- Supervisor restarts PortBridge
- New Go port spawned automatically

### Instance Crashes
- Instance supervisor restarts failed children
- Both Bridge and SocketServer restart if needed
- Active connections dropped
- Clients reconnect automatically

### Startup Failures
- WASM file not found → {:stop, :wasm_file_not_found}
- Port executable missing → {:stop, :port_executable_not_found}
- Port already in use → Crash with bind error

## Performance Considerations

### Bottlenecks
1. **Port Communication:** Binary copy overhead
2. **WASM Call Cost:** Function call overhead into WASM
3. **Socket I/O:** TCP connection handling

### Optimizations
1. **Binary Protocol:** Minimal serialization overhead
2. **Packet Mode:** 4-byte length prefix for framing
3. **No Data Copying:** Binary references where possible
4. **Wazero JIT:** Fast WASM execution

### Scaling
- Multiple instances for isolation
- One instance = one WASM runtime
- Shared-nothing architecture
- Horizontal scaling via multiple nodes

## Future Improvements

1. **Connection Pooling:** Pool across multiple WASM instances
2. **Streaming Results:** Chunked response handling for large results
3. **Metrics:** Prometheus metrics for monitoring
4. **Health Checks:** Built-in health check endpoints
5. **Snapshot/Restore:** Backup and restore instance state
6. **Replication:** Logical replication between instances

## Testing Strategy

### Unit Tests
- Module-level tests for parsers, validators
- Mock dependencies (Registry, Port)

### Integration Tests
- Full stack: Client → Socket → Bridge → Go → WASM
- Test persistence modes
- Test multi-instance isolation

### Property Tests
- PostgreSQL protocol compliance
- Filesystem mount correctness
- Concurrent query handling

## Debugging

### Debug Levels

- `debug: 0` - No debug output
- `debug: 1` - Log major operations
- `debug: 2` - Log all messages with hex dumps
- `debug: 3+` - Reserved for future use

### Helpful Commands

```elixir
# List all instances
PgliteEx.list_instances()

# Get instance details
PgliteEx.instance_info(:my_db)

# Check Registry
Registry.lookup(PgliteEx.Registry, {:instance, :my_db})

# Check process tree
:observer.start()
```

### Logs to Watch

- `[Go Port]` - Go process logs
- `[WASM]` - WASM module logs
- `[Bridge]` - Elixir port bridge logs
- `[SocketServer]` - Connection logs

## References

- [PGlite Documentation](https://github.com/electric-sql/pglite)
- [Wazero Documentation](https://wazero.io/)
- [PostgreSQL Wire Protocol](https://www.postgresql.org/docs/current/protocol.html)
- [Erlang Ports](https://www.erlang.org/doc/reference_manual/ports.html)
