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

  ## Parameters
    - `name` - Atom identifying this instance
    - `config` - Keyword list with configuration:
      - `:port` - TCP port (required)
      - `:host` - Host to bind (default: "127.0.0.1")
      - `:data_dir` - Data directory (default: "memory://")
      - `:username` - Database user (default: "postgres")
      - `:database` - Database name (default: "postgres")
      - `:debug` - Debug level (default: 0)

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
    # Validate required fields
    unless Keyword.has_key?(config, :port) do
      {:error, :port_required}
    else
      # Check if instance already exists
      case lookup_instance(name) do
        {:ok, _pid} ->
          {:error, :already_started}

        {:error, :not_found} ->
          spec = {PgliteEx.Instance, [name: name, config: config]}

          case DynamicSupervisor.start_child(__MODULE__, spec) do
            {:ok, pid} ->
              Logger.info("Started PGlite instance: #{name}")
              {:ok, pid}

            {:error, reason} ->
              Logger.error("Failed to start instance #{name}: #{inspect(reason)}")
              {:error, reason}
          end
      end
    end
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
