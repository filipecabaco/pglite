import Config

# Test configuration
config :pglite_ex,
  # Use different port for tests to avoid conflicts
  socket_port: 5433,
  # Enable verbose logging for tests
  debug: 2
