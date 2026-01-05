defmodule PgliteEx do
  @moduledoc """
  PGliteEx - Elixir bridge to PGlite WebAssembly

  This module provides the main API for interacting with PGlite from Elixir.

  ## Usage Modes

  ### Single Instance Mode (Default)
  By default, PgliteEx starts a single default instance that you can connect to
  immediately on the configured port (default: 5432).

      # In config/config.exs
      config :pglite_ex,
        socket_port: 5432,
        data_dir: "memory://"

      # Connect via psql or any PostgreSQL client
      psql -h localhost -p 5432 -U postgres -d postgres

  ### Multi-Instance Mode
  For running multiple isolated PGlite databases simultaneously:

      # In config/config.exs
      config :pglite_ex,
        multi_instance: true

      # Start instances dynamically
      {:ok, _pid} = PgliteEx.start_instance(:prod_db, port: 5433, data_dir: "./data/prod")
      {:ok, _pid} = PgliteEx.start_instance(:dev_db, port: 5434, data_dir: "memory://")

      # List running instances
      [:prod_db, :dev_db] = PgliteEx.list_instances()

      # Stop an instance
      :ok = PgliteEx.stop_instance(:dev_db)
  """

  alias PgliteEx.Bridge.PortBridge
  alias PgliteEx.InstanceSupervisor

  @doc """
  Execute a raw PostgreSQL wire protocol message.

  This is a low-level function that sends a PostgreSQL wire protocol message
  directly to PGlite and returns the raw response.

  ## Examples

      iex> message = build_query_message("SELECT 1")
      iex> {:ok, response} = PgliteEx.exec_protocol_raw(message)
      {:ok, <<...>>}
  """
  @spec exec_protocol_raw(binary()) :: {:ok, binary()} | {:error, term()}
  def exec_protocol_raw(message) when is_binary(message) do
    PortBridge.exec_protocol_raw(message)
  end

  @doc """
  Get the version of PGlite running in the WASM module.

  ## Examples

      iex> PgliteEx.version()
      {:ok, "PostgreSQL 16.0 (PGlite)"}
  """
  @spec version() :: {:ok, String.t()} | {:error, term()}
  def version do
    # TODO: Implement version query
    {:ok, "PGlite 0.1.0 (via Elixir)"}
  end

  @doc """
  Check if the PGlite bridge is ready to accept queries.

  ## Examples

      iex> PgliteEx.ready?()
      true
  """
  @spec ready?() :: boolean()
  def ready? do
    # Check if the bridge GenServer is running
    case Process.whereis(PortBridge) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end

  # Instance Management API

  @doc """
  Start a new PGlite instance.

  This function is only available when running in multi-instance mode.
  In single-instance mode, a default instance is started automatically.

  ## Parameters
    - `name` - Atom identifying this instance (must be unique)
    - `config` - Keyword list with configuration:
      - `:port` - TCP port for PostgreSQL connections (required)
      - `:host` - Host to bind (default: "127.0.0.1")
      - `:data_dir` - Data directory (default: "memory://")
        - `"memory://"` - In-memory database (ephemeral)
        - `"./path"` or `"file://path"` - File-based persistence
      - `:username` - PostgreSQL username (default: "postgres")
      - `:database` - Database name (default: "postgres")
      - `:debug` - Debug level 0-5 (default: 0)

  ## Examples

      # Start an ephemeral database
      {:ok, pid} = PgliteEx.start_instance(:temp_db,
        port: 5433,
        data_dir: "memory://"
      )

      # Start a persistent database
      {:ok, pid} = PgliteEx.start_instance(:prod_db,
        port: 5434,
        data_dir: "./data/production"
      )

  ## Errors
    - `{:error, :port_required}` - Port not specified in config
    - `{:error, :already_started}` - Instance with this name already exists
  """
  @spec start_instance(atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_instance(name, config) when is_atom(name) and is_list(config) do
    InstanceSupervisor.start_instance(name, config)
  end

  @doc """
  Stop a running PGlite instance.

  This will gracefully shut down the instance, closing all client connections
  and terminating the WASM runtime. In memory mode, all data will be lost.

  ## Examples

      :ok = PgliteEx.stop_instance(:temp_db)

  ## Errors
    - `{:error, :not_found}` - No instance with this name exists
  """
  @spec stop_instance(atom()) :: :ok | {:error, :not_found}
  def stop_instance(name) when is_atom(name) do
    InstanceSupervisor.stop_instance(name)
  end

  @doc """
  List all running PGlite instances.

  Returns a list of instance names (atoms).

  ## Examples

      PgliteEx.list_instances()
      # => [:default, :prod_db, :dev_db]

  In single-instance mode, this will return `[:default]` for the
  automatically started instance.
  """
  @spec list_instances() :: [atom()]
  def list_instances do
    InstanceSupervisor.list_instances()
  end

  @doc """
  Get information about a running instance.

  Returns details about the instance including its process ID and status.

  ## Examples

      {:ok, info} = PgliteEx.instance_info(:prod_db)
      # => {:ok, %{name: :prod_db, pid: #PID<...>, running: true}}

  ## Errors
    - `{:error, :not_found}` - No instance with this name exists
  """
  @spec instance_info(atom()) :: {:ok, map()} | {:error, :not_found}
  def instance_info(name) when is_atom(name) do
    InstanceSupervisor.instance_info(name)
  end
end
