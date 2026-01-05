package main

import (
	"bufio"
	"context"
	"encoding/binary"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/imports/emscripten"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

// PGliteInstance manages a single PGlite WASM instance
type PGliteInstance struct {
	runtime wazero.Runtime
	module  api.Module
	memory  api.Memory
	ctx     context.Context

	// Buffers for WASM communication (mirrors TypeScript implementation)
	outputData   []byte // Data to send to WASM
	inputData    []byte // Data received from WASM
	readOffset   int
	writeOffset  int
	keepRawResp  bool

	mu sync.Mutex
}

const (
	// Buffer sizes matching PGlite TypeScript implementation
	defaultRecvBufSize = 1 * 1024 * 1024 // 1MB
	maxBufferSize      = 1 << 30          // 1GB
)

// Config holds PGlite configuration from environment variables
type Config struct {
	WASMPath string
	DataDir  string
	Username string
	Database string
	Debug    int
}

// readConfig reads configuration from environment variables
func readConfig() *Config {
	config := &Config{
		WASMPath: os.Getenv("PGLITE_WASM_PATH"),
		DataDir:  os.Getenv("PGLITE_DATA_DIR"),
		Username: os.Getenv("PGLITE_USERNAME"),
		Database: os.Getenv("PGLITE_DATABASE"),
		Debug:    0,
	}

	// Set defaults
	if config.WASMPath == "" {
		config.WASMPath = "../priv/pglite/pglite.wasm"
	}
	if config.DataDir == "" {
		config.DataDir = "memory://"
	}
	if config.Username == "" {
		config.Username = "postgres"
	}
	if config.Database == "" {
		config.Database = "postgres"
	}

	// Parse debug level
	if debugStr := os.Getenv("PGLITE_DEBUG"); debugStr != "" {
		if debug, err := fmt.Sscanf(debugStr, "%d", &config.Debug); err == nil && debug == 1 {
			// Successfully parsed
		}
	}

	return config
}

// log prints the configuration (for debugging)
func (c *Config) log() {
	log.Printf("Configuration:")
	log.Printf("  WASM Path: %s", c.WASMPath)
	log.Printf("  Data Dir:  %s", c.DataDir)
	log.Printf("  Username:  %s", c.Username)
	log.Printf("  Database:  %s", c.Database)
	log.Printf("  Debug:     %d", c.Debug)
}

// configureFilesystem sets up filesystem mounting for the WASM module
func configureFilesystem(moduleConfig wazero.ModuleConfig, dataDir string) error {
	// Parse data directory
	isMemory := dataDir == "" || dataDir == "memory://"

	if isMemory {
		log.Printf("Using in-memory filesystem (ephemeral)")
		// No additional filesystem configuration needed for memory mode
		return nil
	}

	// Strip file:// prefix if present
	hostPath := dataDir
	if len(dataDir) >= 7 && dataDir[:7] == "file://" {
		hostPath = dataDir[7:]
	}

	// Expand relative paths to absolute
	absPath, err := filepath.Abs(hostPath)
	if err != nil {
		return fmt.Errorf("failed to resolve path %s: %w", hostPath, err)
	}

	// Ensure directory exists
	if err := os.MkdirAll(absPath, 0755); err != nil {
		return fmt.Errorf("failed to create data directory %s: %w", absPath, err)
	}

	log.Printf("Mounting host directory %s to WASM filesystem at /pgdata", absPath)

	// Mount the host directory into the WASM filesystem
	// PGlite will see this as /pgdata inside the WASM environment
	moduleConfig.WithFSConfig(wazero.NewFSConfig().
		WithDirMount(absPath, "/pgdata"))

	log.Printf("File persistence enabled: data will be stored in %s", absPath)

	return nil
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	log.Println("PGlite WASM Port starting...")

	// Read configuration from environment
	config := readConfig()
	config.log()

	if _, err := os.Stat(config.WASMPath); os.IsNotExist(err) {
		log.Fatalf("WASM file not found: %s", config.WASMPath)
	}

	log.Printf("Loading WASM from: %s", config.WASMPath)

	// Read WASM bytes
	wasmBytes, err := os.ReadFile(config.WASMPath)
	if err != nil {
		log.Fatalf("Failed to read WASM file: %v", err)
	}

	log.Printf("WASM file loaded: %d bytes", len(wasmBytes))

	// Create PGlite instance
	instance, err := NewPGliteInstance(context.Background(), wasmBytes, config)
	if err != nil {
		log.Fatalf("Failed to create PGlite instance: %v", err)
	}
	defer instance.Close()

	log.Println("PGlite instance initialized successfully")
	log.Println("Ready to accept protocol messages on stdin")

	// Main loop: read from stdin, process, write to stdout
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4*1024*1024), 4*1024*1024) // 4MB buffer

	for scanner.Scan() {
		message := scanner.Bytes()

		if len(message) == 0 {
			continue
		}

		// Execute protocol message
		response, err := instance.ExecProtocolRaw(message)
		if err != nil {
			log.Printf("Error executing protocol: %v", err)
			// Send error response to Elixir
			writeResponse([]byte(fmt.Sprintf("ERROR: %v", err)))
			continue
		}

		// Send response back to Elixir
		writeResponse(response)
	}

	if err := scanner.Err(); err != nil {
		log.Fatalf("Error reading stdin: %v", err)
	}
}

// NewPGliteInstance creates a new PGlite WASM instance
func NewPGliteInstance(ctx context.Context, wasmBytes []byte, config *Config) (*PGliteInstance, error) {
	inst := &PGliteInstance{
		ctx:         ctx,
		inputData:   make([]byte, defaultRecvBufSize),
		outputData:  make([]byte, 0),
		keepRawResp: true,
	}

	// Create runtime
	runtimeConfig := wazero.NewRuntimeConfig()
	inst.runtime = wazero.NewRuntimeWithConfig(ctx, runtimeConfig)

	// Instantiate WASI
	if _, err := wasi_snapshot_preview1.Instantiate(ctx, inst.runtime); err != nil {
		return nil, fmt.Errorf("failed to instantiate WASI: %w", err)
	}

	// Instantiate Emscripten functions
	if _, err := emscripten.Instantiate(ctx, inst.runtime); err != nil {
		return nil, fmt.Errorf("failed to instantiate Emscripten: %w", err)
	}

	// Compile module
	compiledModule, err := inst.runtime.CompileModule(ctx, wasmBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to compile module: %w", err)
	}

	// Configure module with filesystem mounting based on data_dir
	moduleConfig := wazero.NewModuleConfig().
		WithName("pglite").
		WithStdout(os.Stdout).
		WithStderr(os.Stderr)

	// Handle filesystem configuration based on data_dir
	if err := configureFilesystem(moduleConfig, config.DataDir); err != nil {
		return nil, fmt.Errorf("failed to configure filesystem: %w", err)
	}

	inst.module, err = inst.runtime.InstantiateModule(ctx, compiledModule, moduleConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to instantiate module: %w", err)
	}

	// Get memory
	inst.memory = inst.module.Memory()
	if inst.memory == nil {
		return nil, fmt.Errorf("module has no exported memory")
	}

	log.Printf("WASM memory size: %d bytes", inst.memory.Size())

	// Initialize database
	if err := inst.initDatabase(); err != nil {
		return nil, fmt.Errorf("failed to initialize database: %w", err)
	}

	return inst, nil
}

// initDatabase calls _pgl_initdb and _pgl_backend
// This mirrors packages/pglite/src/pglite.ts:476-521
func (inst *PGliteInstance) initDatabase() error {
	log.Println("Initializing PostgreSQL database...")

	// Call _pgl_initdb()
	initdb := inst.module.ExportedFunction("_pgl_initdb")
	if initdb == nil {
		return fmt.Errorf("_pgl_initdb function not found")
	}

	results, err := initdb.Call(inst.ctx)
	if err != nil {
		return fmt.Errorf("_pgl_initdb failed: %w", err)
	}

	if len(results) == 0 || results[0] == 0 {
		return fmt.Errorf("_pgl_initdb returned 0 (failure)")
	}

	log.Println("Database initialized successfully")

	// Call _pgl_backend()
	backend := inst.module.ExportedFunction("_pgl_backend")
	if backend == nil {
		return fmt.Errorf("_pgl_backend function not found")
	}

	_, err = backend.Call(inst.ctx)
	if err != nil {
		return fmt.Errorf("_pgl_backend failed: %w", err)
	}

	log.Println("PostgreSQL backend started")

	return nil
}

// ExecProtocolRaw executes a PostgreSQL wire protocol message
// This mirrors packages/pglite/src/pglite.ts:658-681 (execProtocolRawSync)
func (inst *PGliteInstance) ExecProtocolRaw(message []byte) ([]byte, error) {
	inst.mu.Lock()
	defer inst.mu.Unlock()

	// Reset offsets
	inst.readOffset = 0
	inst.writeOffset = 0
	inst.outputData = message

	// Reset input buffer if needed
	if inst.keepRawResp && len(inst.inputData) != defaultRecvBufSize {
		inst.inputData = make([]byte, defaultRecvBufSize)
	}

	if len(message) == 0 {
		return nil, fmt.Errorf("empty message")
	}

	// Get first byte (message type)
	firstByte := uint64(message[0])
	msgLength := uint64(len(message))

	if inst.module == nil {
		return nil, fmt.Errorf("WASM module not initialized")
	}

	// Call _interactive_one(message.length, message[0])
	interactiveOne := inst.module.ExportedFunction("_interactive_one")
	if interactiveOne == nil {
		return nil, fmt.Errorf("_interactive_one function not found")
	}

	_, err := interactiveOne.Call(inst.ctx, msgLength, firstByte)
	if err != nil {
		return nil, fmt.Errorf("_interactive_one failed: %w", err)
	}

	// Clear output buffer
	inst.outputData = nil

	// Extract response from input buffer
	if inst.keepRawResp && inst.writeOffset > 0 {
		response := make([]byte, inst.writeOffset)
		copy(response, inst.inputData[:inst.writeOffset])
		return response, nil
	}

	return []byte{}, nil
}

// Close closes the WASM instance
func (inst *PGliteInstance) Close() error {
	if inst.runtime != nil {
		return inst.runtime.Close(inst.ctx)
	}
	return nil
}

// writeResponse writes a response to stdout in the format Elixir expects
// Format: <4 bytes length><data>
func writeResponse(data []byte) {
	// Write length prefix (4 bytes, big endian)
	lengthBuf := make([]byte, 4)
	binary.BigEndian.PutUint32(lengthBuf, uint32(len(data)))

	os.Stdout.Write(lengthBuf)
	os.Stdout.Write(data)
	os.Stdout.Sync()
}
