defmodule PgliteEx.InstanceSupervisor do
  @moduledoc """
  Dynamic supervisor for managing multiple PGlite instances.

  Allows starting, stopping, and listing PGlite instances at runtime.

  Each instance is fully isolated with its own:
  - WASM runtime (Go port)
  - PostgreSQL socket server
  - Data storage (memory or file)
  - TCP port

  ## Example

      # Start an instance
      {:ok, pid} = PgliteEx.InstanceSupervisor.start_instance(
        :my_db,
        port: 5433,
        data_dir: "memory://"
      )

      # List all instances
      PgliteEx.InstanceSupervisor.list_instances()
      # => [:default, :my_db]

      # Stop an instance
      :ok = PgliteEx.InstanceSupervisor.stop_instance(:my_db)
  """

  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new PGlite instance.

  Creates and supervises a new isolated PGlite instance with its own WASM
  runtime, TCP port, and data storage.

  ## Parameters
    - `name` - Atom identifying this instance (must be unique)
    - `config` - Keyword list with configuration:
      - `:port` - TCP port (required)
      - `:host` - Host to bind (default: "127.0.0.1")
      - `:data_dir` - Data directory (default: "memory://")
      - `:username` - Database user (default: "postgres")
      - `:database` - Database name (default: "postgres")
      - `:debug` - Debug level (default: 0)

  ## Returns
    - `{:ok, pid}` - Instance started successfully
    - `{:error, :port_required}` - Port not specified in config
    - `{:error, :already_started}` - Instance with this name exists
    - `{:error, reason}` - Other startup error

  ## Examples

      {:ok, pid} = PgliteEx.InstanceSupervisor.start_instance(
        :prod_db,
        port: 5433,
        data_dir: "./data/production"
      )

      {:ok, pid} = PgliteEx.InstanceSupervisor.start_instance(
        :temp_db,
        port: 5434,
        data_dir: "memory://"
      )
  """
  def start_instance(name, config) when is_atom(name) and is_list(config) do
    with :ok <- validate_config(config),
         :ok <- ensure_instance_not_running(name),
         {:ok, pid} <- start_supervised_instance(name, config) do
      Logger.info("Started PGlite instance: #{name}")
      {:ok, pid}
    else
      {:error, reason} = error ->
        Logger.error("Failed to start instance #{name}: #{inspect(reason)}")
        error
    end
  end

  # Private helper functions for start_instance

  defp validate_config(config) do
    if Keyword.has_key?(config, :port) do
      :ok
    else
      {:error, :port_required}
    end
  end

  defp ensure_instance_not_running(name) do
    case lookup_instance(name) do
      {:ok, _pid} -> {:error, :already_started}
      {:error, :not_found} -> :ok
    end
  end

  defp start_supervised_instance(name, config) do
    spec = {PgliteEx.Instance, [name: name, config: config]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop a running PGlite instance.

  This will:
  - Close all client connections
  - Shut down the PostgreSQL server
  - Terminate the WASM runtime
  - (If memory mode) Lose all data

  ## Examples

      :ok = PgliteEx.InstanceSupervisor.stop_instance(:my_db)
  """
  def stop_instance(name) when is_atom(name) do
    case lookup_instance(name) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped PGlite instance: #{name}")
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  List all running PGlite instances.

  Returns a list of instance names.

  ## Examples

      PgliteEx.InstanceSupervisor.list_instances()
      # => [:default, :prod_db, :dev_db]
  """
  def list_instances do
    Registry.select(PgliteEx.Registry, [
      {{{:instance, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
  end

  @doc """
  Get information about a running instance.

  ## Examples

      PgliteEx.InstanceSupervisor.instance_info(:default)
      # => {:ok, %{name: :default, pid: #PID<...>, config: [...]}}
  """
  def instance_info(name) when is_atom(name) do
    case lookup_instance(name) do
      {:ok, pid} ->
        # Get config from supervisor state if possible
        # For now, just return basic info
        {:ok, %{name: name, pid: pid, running: Process.alive?(pid)}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # Private helpers

  defp lookup_instance(name) do
    case Registry.lookup(PgliteEx.Registry, {:instance, name}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
