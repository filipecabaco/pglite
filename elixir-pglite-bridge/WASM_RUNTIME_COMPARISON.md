# WASM Runtime Comparison for PGlite Bridge

Research comparing WASM runtimes for running PGlite from Elixir via Ports.

## Requirements

1. **Low Memory Footprint**: Run multiple PGlite instances efficiently
2. **Low CPU Usage**: Minimal overhead for query processing
3. **Emscripten Support**: PGlite needs callbacks (`addFunction`, `_set_read_write_cbs`)
4. **Port Integration**: Communicate with Elixir via Ports (not NIFs - long-running jobs)
5. **Instance Isolation**: Each connection gets its own WASM instance

## Runtime Options Compared

### 1. Wasmtime (Rust) ⭐ **RECOMMENDED**

**Performance:**
- ✅ **Fastest**: 85-90% of native speed
- ✅ Memory: ~25MB per instance
- ✅ Excellent multi-instance support via Rust threads
- ✅ Mature and battle-tested

**Emscripten Support:**
- ⚠️ WASI-focused, but can handle Emscripten
- ✅ Function callbacks via `Func::wrap`
- ✅ Memory exports fully supported
- ✅ Strong WASI implementation helps with syscalls

**Port Integration:**
- ✅ Easy to build single Rust binary
- ✅ Can use stdin/stdout or Unix sockets
- ✅ Excellent error handling
- ✅ Async I/O support with Tokio

**Code Example:**
```rust
use wasmtime::*;

fn main() -> Result<()> {
    let engine = Engine::default();
    let mut store = Store::new(&engine, ());
    let module = Module::from_file(&engine, "pglite.wasm")?;

    // Create callback for PGlite write
    let write_callback = Func::wrap(&mut store, |ptr: i32, len: i32| {
        // Read from WASM memory, send to Elixir
        println!("WASM wrote {} bytes at {}", len, ptr);
    });

    let instance = Instance::new(&mut store, &module, &[write_callback.into()])?;
    Ok(())
}
```

**Pros:**
- Best performance
- Active development
- Great documentation
- Backed by Bytecode Alliance

**Cons:**
- Larger binary size (~10MB)
- More complex API than Wazero

**Sources:**
- [Performance Comparison: Wasmer vs. WASMTime](https://ashourics.medium.com/performance-comparison-analysis-wasmer-vs-wasmtime-48c6f51b536f)
- [Wasmtime Rust Docs](https://docs.wasmtime.dev/api/wasmtime/)

---

### 2. Wazero (Go) ⭐ **STRONG ALTERNATIVE**

**Performance:**
- ⚠️ Slower than Wasmtime (but still good)
- ✅ Memory: ~20MB per instance
- ✅ **Zero dependencies** - pure Go
- ✅ No CGO required

**Emscripten Support:**
- ✅ **Built-in Emscripten package**: `wazero.io/emscripten`
- ✅ Explicit callback support
- ✅ Virtual filesystem for Emscripten
- ✅ Updated for Emscripten 3.1.57+ (2025)

**Port Integration:**
- ✅ **Single binary** - easiest deployment
- ✅ Native Go concurrency (goroutines)
- ✅ Excellent for multiple instances
- ✅ Simple stdin/stdout handling

**Code Example:**
```go
package main

import (
    "context"
    "github.com/tetratelabs/wazero"
    "github.com/tetratelabs/wazero/imports/emscripten"
)

func main() {
    ctx := context.Background()
    r := wazero.NewRuntime(ctx)
    defer r.Close(ctx)

    // Add Emscripten support
    emscripten.MustInstantiate(ctx, r)

    // Load PGlite
    wasm, _ := os.ReadFile("pglite.wasm")
    mod, _ := r.Instantiate(ctx, wasm)

    // Call functions
    mod.ExportedFunction("_pgl_initdb").Call(ctx)
}
```

**Pros:**
- **Easiest to deploy** (single binary)
- Native Emscripten support
- Great for multiple instances
- Simple API
- Good concurrency model

**Cons:**
- Slower execution than Wasmtime
- Smaller ecosystem than Rust/Wasmtime

**Sources:**
- [Wazero Documentation](https://wazero.io/)
- [Wazero Emscripten Support](https://pkg.go.dev/github.com/tetratelabs/wazero)
- [wazero-emscripten-embind](https://github.com/jerbob92/wazero-emscripten-embind)

---

### 3. Wasmer (Rust)

**Performance:**
- ✅ Good: 80-85% of native speed
- ✅ **Lower memory**: ~18MB per instance
- ✅ Good multi-instance support

**Emscripten Support:**
- ✅ Good Emscripten compatibility
- ✅ Function callbacks supported
- ✅ Active development

**Port Integration:**
- ✅ Similar to Wasmtime
- ✅ Rust binary
- ✅ Good I/O handling

**Pros:**
- Lowest memory footprint
- Good performance
- Active community

**Cons:**
- Slightly slower than Wasmtime
- Less mature than Wasmtime

**Sources:**
- [Wasmer vs Wasmtime](https://wasmer.io/wasmer-vs-wasmtime)

---

### 4. Wasmex (Elixir NIF) ❌ **NOT RECOMMENDED**

**Why Not:**
- ❌ NIFs block BEAM schedulers (even dirty schedulers)
- ❌ Long-running database queries are bad for NIFs
- ❌ Less isolation (crashes can affect BEAM)
- ❌ Complex callback mechanism
- ❌ Not designed for long-running processes

**Only use NIFs for:**
- Short computations (<1ms)
- CPU-bound tasks that finish quickly
- Operations that can't afford Port overhead

---

## Recommended Architecture

### Option 1: Rust + Wasmtime Port (Best Performance)

```
┌─────────────────────┐
│  Elixir/Postgrex    │
└──────────┬──────────┘
           │ PostgreSQL Wire Protocol
           ▼
┌─────────────────────┐
│ PgliteEx.Socket     │ GenServer (Elixir)
│ Server              │
└──────────┬──────────┘
           │ Port (stdin/stdout or Unix socket)
           ▼
┌─────────────────────┐
│ pglite-port         │ Rust Binary
│ (Wasmtime)          │ - Manages WASM instances
│                     │ - Handles protocol messages
│                     │ - Spawns threads per connection
└──────────┬──────────┘
           │ WASM function calls
           ▼
┌─────────────────────┐
│ PGlite WASM         │ Multiple instances
│ Instance Pool       │
└─────────────────────┘
```

**Implementation:**
```rust
// src/main.rs
use wasmtime::*;
use std::io::{self, BufRead, Write};

fn main() -> Result<()> {
    let engine = Engine::default();

    // Read messages from Elixir via stdin
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let message = line?;

        // Create new WASM instance for this connection
        let mut store = Store::new(&engine, ());
        let module = Module::from_file(&engine, "pglite.wasm")?;

        // Set up callbacks
        let write_cb = Func::wrap(&mut store, |ptr: i32, len: i32| {
            // Send response back to Elixir
        });

        let instance = Instance::new(&mut store, &module, &[write_cb.into()])?;

        // Process message and send response
        let response = process_protocol_message(&instance, &message)?;
        println!("{}", response); // stdout to Elixir
    }
    Ok(())
}
```

**Elixir Side:**
```elixir
defmodule PgliteEx.WasmPort do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    # Start the Rust port
    port = Port.open({:spawn, "priv/pglite-port"}, [:binary, :exit_status])
    {:ok, %{port: port}}
  end

  def handle_call({:exec_protocol, message}, _from, state) do
    # Send to port
    Port.command(state.port, message <> "\n")

    # Receive response
    receive do
      {^port, {:data, response}} ->
        {:reply, {:ok, response}, state}
    after
      5000 -> {:reply, {:error, :timeout}, state}
    end
  end
end
```

---

### Option 2: Go + Wazero Port (Simplest Deployment)

```
Same architecture as above, but:
- Single Go binary (easier deployment)
- Native goroutines for concurrency
- Built-in Emscripten support
```

**Implementation:**
```go
// main.go
package main

import (
    "bufio"
    "context"
    "fmt"
    "os"
    "github.com/tetratelabs/wazero"
    "github.com/tetratelabs/wazero/imports/emscripten"
)

func main() {
    ctx := context.Background()
    r := wazero.NewRuntime(ctx)
    defer r.Close(ctx)

    emscripten.MustInstantiate(ctx, r)

    // Load WASM
    wasmBytes, _ := os.ReadFile("pglite.wasm")

    scanner := bufio.NewScanner(os.Stdin)
    for scanner.Scan() {
        message := scanner.Bytes()

        // Process in goroutine for concurrency
        go func(msg []byte) {
            // Create instance
            mod, _ := r.Instantiate(ctx, wasmBytes)
            defer mod.Close(ctx)

            // Execute query
            response := processProtocolMessage(mod, msg)

            // Send back to Elixir
            fmt.Println(string(response))
        }(message)
    }
}
```

---

## Final Recommendation

### 🥇 **Best Choice: Go + Wazero**

**Why:**
1. ✅ **Built-in Emscripten support** - PGlite will work out of the box
2. ✅ **Single binary deployment** - no dependencies, easy to distribute
3. ✅ **Great concurrency** - goroutines handle multiple instances efficiently
4. ✅ **Low memory** - ~20MB per instance
5. ✅ **Simple codebase** - easier to maintain
6. ✅ **Good performance** - sufficient for database workloads
7. ✅ **Updated for 2025** - supports latest Emscripten

**When to choose this:**
- Want simplest deployment
- Need proven Emscripten support
- Value stability over max performance
- Team comfortable with Go

### 🥈 **Alternative: Rust + Wasmtime**

**Why:**
1. ✅ **Best performance** - 85-90% native speed
2. ✅ **Lowest latency** - important for query response times
3. ✅ **Most mature** - Bytecode Alliance backing
4. ✅ **Best ecosystem** - more tooling available

**When to choose this:**
- Performance is critical
- Already using Rust elsewhere
- Need absolute best WASM execution speed
- Can handle slightly more complex setup

---

## Implementation Roadmap

### Phase 1: Proof of Concept (Go + Wazero)
1. Create simple Go port that loads PGlite WASM
2. Implement basic stdin/stdout communication
3. Test with simple queries
4. **Estimated time**: 2-3 days

### Phase 2: Protocol Integration
1. Implement PostgreSQL wire protocol in port
2. Handle Emscripten callbacks
3. Test with Postgrex client
4. **Estimated time**: 1 week

### Phase 3: Production Features
1. Connection pooling
2. Error handling
3. Graceful shutdown
4. Monitoring/metrics
5. **Estimated time**: 1-2 weeks

---

## Memory Footprint Calculations

**For 100 concurrent connections:**

| Runtime | Per Instance | 100 Instances | Go Binary | Total |
|---------|-------------|---------------|-----------|-------|
| Wazero (Go) | 20MB | 2GB | 5MB | **2.005GB** |
| Wasmtime (Rust) | 25MB | 2.5GB | 10MB | **2.51GB** |
| Wasmer (Rust) | 18MB | 1.8GB | 10MB | **1.81GB** |

**Note:** With connection pooling and instance reuse, you'd have far fewer instances than connections.

---

## Sources

- [WebAssembly runtimes compared - LogRocket Blog](https://blog.logrocket.com/webassembly-runtimes-compared/)
- [Performance Comparison Analysis: Wasmer vs. WASMTime](https://ashourics.medium.com/performance-comparison-analysis-wasmer-vs-wasmtime-48c6f51b536f)
- [Wazero Documentation](https://wazero.io/)
- [wazero-emscripten-embind](https://github.com/jerbob92/wazero-emscripten-embind)
- [Wasmtime Documentation](https://docs.wasmtime.dev/api/wasmtime/)
- [Elixir and Rust is a good mix](https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/)
- [Elixir Ports and NIFs Best Practices](https://softwarepatternslexicon.com/patterns-elixir/14/2/)
- [Interoperability in 2025: beyond the Erlang VM](http://elixir-lang.org/blog/2025/08/18/interop-and-portability/)
