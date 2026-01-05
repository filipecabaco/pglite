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

	// Filesystem configuration
	wasmDataMountPoint = "/pgdata"        // Mount point inside WASM for persistent data
	memoryProtocol     = "memory://"      // Protocol prefix for in-memory storage
	fileProtocol       = "file://"        // Protocol prefix for file storage
	defaultDirPerms    = 0755             // Default directory permissions
)

// Config holds PGlite configuration from environment variables
type Config struct {
	WASMPath string
	DataDir  string
	Username string
	Database string
	Debug    int
}

// readConfig reads configuration from environment variables with sensible defaults
func readConfig() *Config {
	config := &Config{
		WASMPath: getEnvOrDefault("PGLITE_WASM_PATH", "../priv/pglite/pglite.wasm"),
		DataDir:  getEnvOrDefault("PGLITE_DATA_DIR", memoryProtocol),
		Username: getEnvOrDefault("PGLITE_USERNAME", "postgres"),
		Database: getEnvOrDefault("PGLITE_DATABASE", "postgres"),
		Debug:    parseDebugLevel(os.Getenv("PGLITE_DEBUG")),
	}

	return config
}

// getEnvOrDefault retrieves environment variable value or returns default
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// parseDebugLevel parses debug level from string (0-5), defaults to 0
func parseDebugLevel(debugStr string) int {
	if debugStr == "" {
		return 0
	}

	var level int
	if _, err := fmt.Sscanf(debugStr, "%d", &level); err != nil {
		log.Printf("Warning: Invalid debug level '%s', using 0", debugStr)
		return 0
	}

	// Clamp to valid range
	if level < 0 {
		return 0
	}
	if level > 5 {
		return 5
	}

	return level
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

// configureFilesystem sets up filesystem mounting for the WASM module.
// It supports two modes:
//   - In-memory: dataDir is empty or "memory://" - no persistence
//   - File-based: dataDir is a path - mounts host directory to WASM filesystem
//
// File paths can use "file://" prefix or be plain paths (relative or absolute).
func configureFilesystem(moduleConfig wazero.ModuleConfig, dataDir string) error {
	// Check if using in-memory mode
	if isMemoryMode(dataDir) {
		log.Printf("Filesystem mode: in-memory (ephemeral - data will not persist)")
		return nil
	}

	// Extract and validate the host path
	hostPath, err := extractHostPath(dataDir)
	if err != nil {
		return fmt.Errorf("invalid data directory configuration: %w", err)
	}

	// Expand to absolute path for clarity and reliability
	absPath, err := filepath.Abs(hostPath)
	if err != nil {
		return fmt.Errorf("failed to resolve path '%s' to absolute path: %w", hostPath, err)
	}

	// Create directory structure if it doesn't exist
	if err := os.MkdirAll(absPath, defaultDirPerms); err != nil {
		return fmt.Errorf("failed to create data directory '%s': %w", absPath, err)
	}

	log.Printf("Filesystem mode: persistent")
	log.Printf("  Host path: %s", absPath)
	log.Printf("  WASM mount point: %s", wasmDataMountPoint)

	// Mount the host directory into the WASM filesystem using wazero's FSConfig
	// The WASM module will see this as wasmDataMountPoint (/pgdata)
	moduleConfig.WithFSConfig(wazero.NewFSConfig().
		WithDirMount(absPath, wasmDataMountPoint))

	log.Printf("File persistence enabled successfully")

	return nil
}

// isMemoryMode checks if the data directory indicates in-memory mode
func isMemoryMode(dataDir string) bool {
	return dataDir == "" || dataDir == memoryProtocol
}

// extractHostPath extracts the filesystem path from a data directory string,
// handling "file://" prefix and returning the clean path
func extractHostPath(dataDir string) (string, error) {
	if dataDir == "" {
		return "", fmt.Errorf("data directory cannot be empty string")
	}

	// Strip file:// protocol prefix if present
	if len(dataDir) > len(fileProtocol) && dataDir[:len(fileProtocol)] == fileProtocol {
		return dataDir[len(fileProtocol):], nil
	}

	// Return as-is (could be relative or absolute path)
	return dataDir, nil
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
