import Config

# PGliteEx configuration
config :pglite_ex,
  # Path to PGlite WASM file
  wasm_path: "priv/pglite/pglite.wasm",
  # Socket server configuration
  socket_port: 5432,
  socket_host: "127.0.0.1",
  # Debug level (0-5)
  # 0 = no debug
  # 1 = basic logging
  # 2 = detailed protocol logging
  # 3+ = verbose WASM interaction logging
  debug: 0,
  # Initial WASM memory (in bytes)
  initial_memory: 256 * 1024 * 1024

# Import environment specific config
import_config "#{config_env()}.exs"
