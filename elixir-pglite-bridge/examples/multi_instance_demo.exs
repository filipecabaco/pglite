#!/usr/bin/env elixir

# Multi-Instance PGliteEx Demo
#
# This example demonstrates how to use PGliteEx to run multiple isolated
# PostgreSQL databases simultaneously.
#
# Prerequisites:
#   - Mix dependencies installed: mix deps.get
#   - Go port built: cd pglite_port && make install
#   - PGlite WASM downloaded to priv/pglite/
#
# Run with: mix run examples/multi_instance_demo.exs

Mix.install([
  {:postgrex, "~> 0.17"}
])

# Ensure PgliteEx is started in multi-instance mode
Application.put_env(:pglite_ex, :multi_instance, true)
{:ok, _} = Application.ensure_all_started(:pglite_ex)

defmodule MultiInstanceDemo do
  @moduledoc """
  Demonstrates multi-instance PGliteEx usage.
  """

  require Logger

  def run do
    Logger.info("=== PGliteEx Multi-Instance Demo ===\n")

    # Clean up any existing instances
    cleanup_existing_instances()

    # Demo 1: In-memory ephemeral database
    demo_ephemeral_database()

    # Demo 2: Persistent database
    demo_persistent_database()

    # Demo 3: Multiple isolated instances
    demo_multiple_instances()

    # Demo 4: Instance management API
    demo_instance_management()

    Logger.info("\n=== Demo Complete ===")
    Logger.info("All instances stopped. Exiting.")
  end

  defp cleanup_existing_instances do
    Logger.info("Cleaning up any existing instances...")

    PgliteEx.list_instances()
    |> Enum.each(fn name ->
      Logger.info("  Stopping existing instance: #{name}")
      PgliteEx.stop_instance(name)
    end)

    Logger.info("")
  end

  defp demo_ephemeral_database do
    Logger.info("Demo 1: Ephemeral In-Memory Database")
    Logger.info("=" |> String.duplicate(50))

    # Start an ephemeral database
    Logger.info("Starting ephemeral database on port 5432...")

    {:ok, _pid} =
      PgliteEx.start_instance(:ephemeral_db,
        port: 5432,
        data_dir: "memory://"
      )

    Logger.info("✓ Instance started: :ephemeral_db")
    Logger.info("  Connect with: psql -h localhost -p 5432 -U postgres -d postgres")
    Logger.info("  Data stored: In-memory (will be lost on restart)")

    # Give it a moment to start
    Process.sleep(1000)

    # Connect and run a query
    case connect_and_query(5432) do
      :ok ->
        Logger.info("✓ Successfully executed query")

      {:error, reason} ->
        Logger.error("✗ Failed to connect: #{inspect(reason)}")
    end

    # Stop the instance
    Logger.info("Stopping ephemeral database...")
    :ok = PgliteEx.stop_instance(:ephemeral_db)
    Logger.info("✓ Instance stopped (all data lost)")
    Logger.info("")
  end

  defp demo_persistent_database do
    Logger.info("Demo 2: Persistent File-Based Database")
    Logger.info("=" |> String.duplicate(50))

    data_dir = Path.join(System.tmp_dir(), "pglite_demo_persistent")
    Logger.info("Starting persistent database on port 5433...")
    Logger.info("  Data directory: #{data_dir}")

    {:ok, _pid} =
      PgliteEx.start_instance(:persistent_db,
        port: 5433,
        data_dir: data_dir
      )

    Logger.info("✓ Instance started: :persistent_db")
    Logger.info("  Connect with: psql -h localhost -p 5433 -U postgres -d postgres")
    Logger.info("  Data stored: #{data_dir} (survives restarts)")

    Process.sleep(1000)

    # Connect and run a query
    case connect_and_query(5433) do
      :ok ->
        Logger.info("✓ Successfully executed query")

      {:error, reason} ->
        Logger.error("✗ Failed to connect: #{inspect(reason)}")
    end

    # Stop the instance
    Logger.info("Stopping persistent database...")
    :ok = PgliteEx.stop_instance(:persistent_db)
    Logger.info("✓ Instance stopped")
    Logger.info("  Note: Data still exists in #{data_dir}")

    # Clean up the data directory
    File.rm_rf(data_dir)
    Logger.info("  Cleaned up data directory")
    Logger.info("")
  end

  defp demo_multiple_instances do
    Logger.info("Demo 3: Multiple Isolated Instances")
    Logger.info("=" |> String.duplicate(50))

    # Start three instances for different purposes
    instances = [
      {:production_db, 5434, "./data/production"},
      {:staging_db, 5435, "./data/staging"},
      {:development_db, 5436, "memory://"}
    ]

    Logger.info("Starting #{length(instances)} isolated instances...")

    Enum.each(instances, fn {name, port, data_dir} ->
      {:ok, _pid} =
        PgliteEx.start_instance(name,
          port: port,
          data_dir: data_dir
        )

      mode = if String.starts_with?(data_dir, "memory://"), do: "ephemeral", else: "persistent"
      Logger.info("✓ #{name} started on port #{port} (#{mode})")
    end)

    # List all instances
    Logger.info("\nActive instances:")
    all_instances = PgliteEx.list_instances()

    Enum.each(all_instances, fn name ->
      {:ok, info} = PgliteEx.instance_info(name)
      Logger.info("  - #{info.name} (pid: #{inspect(info.pid)}, running: #{info.running})")
    end)

    # Stop all instances
    Logger.info("\nStopping all instances...")

    Enum.each(instances, fn {name, _port, _data_dir} ->
      :ok = PgliteEx.stop_instance(name)
      Logger.info("✓ #{name} stopped")
    end)

    # Clean up data directories
    ["./data/production", "./data/staging"]
    |> Enum.each(&File.rm_rf/1)

    Logger.info("")
  end

  defp demo_instance_management do
    Logger.info("Demo 4: Instance Management API")
    Logger.info("=" |> String.duplicate(50))

    # Start an instance
    Logger.info("Starting instance :api_demo...")

    {:ok, pid} =
      PgliteEx.start_instance(:api_demo,
        port: 5437,
        data_dir: "memory://"
      )

    Logger.info("✓ Instance started with pid: #{inspect(pid)}")

    # Get instance info
    {:ok, info} = PgliteEx.instance_info(:api_demo)

    Logger.info("Instance information:")
    Logger.info("  Name: #{info.name}")
    Logger.info("  PID: #{inspect(info.pid)}")
    Logger.info("  Running: #{info.running}")

    # Try to start duplicate (should fail)
    Logger.info("\nAttempting to start duplicate instance...")

    case PgliteEx.start_instance(:api_demo, port: 5438, data_dir: "memory://") do
      {:error, :already_started} ->
        Logger.info("✓ Correctly prevented duplicate instance")

      other ->
        Logger.error("✗ Unexpected result: #{inspect(other)}")
    end

    # List instances
    instances = PgliteEx.list_instances()
    Logger.info("\nCurrent instances: #{inspect(instances)}")

    # Stop instance
    Logger.info("Stopping instance...")
    :ok = PgliteEx.stop_instance(:api_demo)
    Logger.info("✓ Instance stopped")

    # Verify it's stopped
    case PgliteEx.instance_info(:api_demo) do
      {:error, :not_found} ->
        Logger.info("✓ Instance correctly removed from registry")

      other ->
        Logger.error("✗ Unexpected result: #{inspect(other)}")
    end

    Logger.info("")
  end

  defp connect_and_query(port) do
    Logger.info("Connecting to PostgreSQL on port #{port}...")

    # Connect to the database
    case Postgrex.start_link(
           hostname: "localhost",
           port: port,
           username: "postgres",
           database: "postgres",
           # PGlite uses trust auth by default
           password: ""
         ) do
      {:ok, conn} ->
        Logger.info("✓ Connected to database")

        # Run a simple query
        Logger.info("Executing: SELECT version()")

        case Postgrex.query(conn, "SELECT version()", []) do
          {:ok, result} ->
            Logger.info("Query result:")
            Logger.info("  Columns: #{inspect(result.columns)}")
            Logger.info("  Rows: #{inspect(result.rows)}")

            # Create a table and insert data
            Logger.info("\nCreating table and inserting data...")

            {:ok, _} =
              Postgrex.query(conn, "CREATE TABLE IF NOT EXISTS demo (id INT, name TEXT)", [])

            {:ok, _} = Postgrex.query(conn, "INSERT INTO demo VALUES (1, 'Hello PGlite')", [])
            {:ok, result} = Postgrex.query(conn, "SELECT * FROM demo", [])

            Logger.info("✓ Table created and data inserted")
            Logger.info("  Data: #{inspect(result.rows)}")

            GenServer.stop(conn)
            :ok

          {:error, error} ->
            GenServer.stop(conn)
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end

# Run the demo
MultiInstanceDemo.run()
