#!/usr/bin/env elixir

# Simple PGliteEx Query Example
#
# This example demonstrates the simplest way to use PGliteEx with a single
# default instance and run basic SQL queries.
#
# Prerequisites:
#   - Mix dependencies installed: mix deps.get
#   - Go port built: cd pglite_port && make install
#   - PGlite WASM downloaded to priv/pglite/
#
# Run with: mix run examples/simple_query.exs

Mix.install([
  {:postgrex, "~> 0.17"}
])

# Configure PgliteEx to use single-instance mode (default)
Application.put_env(:pglite_ex, :socket_port, 5432)
Application.put_env(:pglite_ex, :socket_host, "127.0.0.1")
Application.put_env(:pglite_ex, :data_dir, "memory://")

# Start the application
{:ok, _} = Application.ensure_all_started(:pglite_ex)

IO.puts("=== Simple PGliteEx Query Example ===\n")
IO.puts("Starting PGlite on port 5432...")

# Give the instance a moment to start
Process.sleep(2000)

# Check if the instance is ready
if PgliteEx.ready?() do
  IO.puts("✓ PGlite instance ready!\n")
else
  IO.puts("✗ PGlite instance not ready")
  System.halt(1)
end

# Connect using Postgrex
IO.puts("Connecting to PostgreSQL...")

{:ok, conn} =
  Postgrex.start_link(
    hostname: "localhost",
    port: 5432,
    username: "postgres",
    database: "postgres",
    password: ""
  )

IO.puts("✓ Connected!\n")

# Example 1: Check PostgreSQL version
IO.puts("Example 1: Check PostgreSQL Version")
IO.puts("=" |> String.duplicate(40))
{:ok, result} = Postgrex.query(conn, "SELECT version()", [])

Enum.each(result.rows, fn [version] ->
  IO.puts("PostgreSQL Version: #{version}")
end)

IO.puts("")

# Example 2: Create a table
IO.puts("Example 2: Create a Table")
IO.puts("=" |> String.duplicate(40))

{:ok, _} =
  Postgrex.query(
    conn,
    """
    CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """,
    []
  )

IO.puts("✓ Table 'users' created")
IO.puts("")

# Example 3: Insert data
IO.puts("Example 3: Insert Data")
IO.puts("=" |> String.duplicate(40))

users = [
  {"Alice", "alice@example.com"},
  {"Bob", "bob@example.com"},
  {"Charlie", "charlie@example.com"}
]

Enum.each(users, fn {name, email} ->
  {:ok, _} =
    Postgrex.query(
      conn,
      "INSERT INTO users (name, email) VALUES ($1, $2)",
      [name, email]
    )

  IO.puts("✓ Inserted: #{name} <#{email}>")
end)

IO.puts("")

# Example 4: Query data
IO.puts("Example 4: Query All Users")
IO.puts("=" |> String.duplicate(40))

{:ok, result} =
  Postgrex.query(
    conn,
    "SELECT id, name, email, created_at FROM users ORDER BY id",
    []
  )

IO.puts("Found #{length(result.rows)} users:\n")

Enum.each(result.rows, fn [id, name, email, created_at] ->
  IO.puts("  #{id}. #{name}")
  IO.puts("     Email: #{email}")
  IO.puts("     Created: #{created_at}")
  IO.puts("")
end)

# Example 5: Aggregate query
IO.puts("Example 5: Aggregate Query")
IO.puts("=" |> String.duplicate(40))

{:ok, result} =
  Postgrex.query(
    conn,
    "SELECT COUNT(*) as user_count, MAX(created_at) as latest FROM users",
    []
  )

[[count, latest]] = result.rows
IO.puts("Total users: #{count}")
IO.puts("Latest user created at: #{latest}")
IO.puts("")

# Example 6: Transactions
IO.puts("Example 6: Transaction Example")
IO.puts("=" |> String.duplicate(40))

Postgrex.transaction(conn, fn transaction_conn ->
  # Insert a user
  {:ok, _} =
    Postgrex.query(
      transaction_conn,
      "INSERT INTO users (name, email) VALUES ($1, $2)",
      ["Dave", "dave@example.com"]
    )

  IO.puts("✓ Inserted Dave in transaction")

  # Query within transaction
  {:ok, result} =
    Postgrex.query(
      transaction_conn,
      "SELECT COUNT(*) FROM users WHERE name = $1",
      ["Dave"]
    )

  [[count]] = result.rows
  IO.puts("✓ Found #{count} user(s) named Dave")

  :ok
end)

IO.puts("✓ Transaction committed")
IO.puts("")

# Example 7: JSON support
IO.puts("Example 7: JSON Support")
IO.puts("=" |> String.duplicate(40))

{:ok, _} =
  Postgrex.query(
    conn,
    """
    CREATE TABLE products (
      id SERIAL PRIMARY KEY,
      name TEXT,
      metadata JSONB
    )
    """,
    []
  )

{:ok, _} =
  Postgrex.query(
    conn,
    "INSERT INTO products (name, metadata) VALUES ($1, $2)",
    ["Laptop", %{"brand" => "Acme", "price" => 999.99, "in_stock" => true}]
  )

{:ok, result} = Postgrex.query(conn, "SELECT name, metadata FROM products", [])
[[name, metadata]] = result.rows

IO.puts("Product: #{name}")
IO.puts("Metadata: #{inspect(metadata)}")
IO.puts("")

# Cleanup
GenServer.stop(conn)

IO.puts("\n=== Example Complete ===")
IO.puts("Database connection closed.")
IO.puts("\nNote: Since we're using memory:// mode, all data will be lost")
IO.puts("when the PgliteEx application stops.")
