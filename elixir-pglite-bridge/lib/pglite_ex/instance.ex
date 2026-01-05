defmodule PgliteEx.Instance do
  @moduledoc """
  Supervisor for a single PGlite instance.

  Each instance manages:
  - A Go port running PGlite WASM
  - A PostgreSQL socket server
  - Instance-specific configuration

  Multiple instances can run simultaneously on different ports with
  independent data.

  ## Architecture

  Each instance creates two child processes:
  1. `PgliteEx.Bridge.PortBridge` - Manages the Go port running WASM
  2. `PgliteEx.SocketServer` - Accepts PostgreSQL wire protocol connections

  All processes are registered in `PgliteEx.Registry` using unique names
  derived from the instance name.
  """

  use Supervisor
  require Logger

  # Constants for data directory configuration
  @memory_protocol "memory://"
  @file_protocol "file://"

  @doc """
  Start a PGlite instance supervisor.

  ## Options
    - `:name` - Instance name (atom, required)
    - `:config` - Instance configuration (keyword list, required)
      - `:port` - TCP port for PostgreSQL connections (required)
      - `:host` - Host to bind to (default: "127.0.0.1")
      - `:data_dir` - Data directory (default: "memory://")
        - `"memory://"` - In-memory (ephemeral)
        - `"./path"` - File persistence (future)
      - `:username` - PostgreSQL username (default: "postgres")
      - `:database` - Database name (default: "postgres")
      - `:debug` - Debug level 0-5 (default: 0)

  ## Examples

      {:ok, pid} = PgliteEx.Instance.start_link(
        name: :my_db,
        config: [port: 5432, data_dir: "memory://"]
      )
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    config = Keyword.fetch!(opts, :config)

    # Extract configuration
    port = Keyword.fetch!(config, :port)
    host = Keyword.get(config, :host, "127.0.0.1")
    data_dir = Keyword.get(config, :data_dir, "memory://")
    username = Keyword.get(config, :username, "postgres")
    database = Keyword.get(config, :database, "postgres")
    debug = Keyword.get(config, :debug, 0)
    wasm_path = Keyword.get(config, :wasm_path, Application.get_env(:pglite_ex, :wasm_path))

    # Validate data_dir
    case parse_data_dir(data_dir) do
      {:memory, _} ->
        Logger.info("Instance #{name}: Starting with in-memory database (ephemeral)")

      {:file, path} ->
        Logger.info("Instance #{name}: Starting with file persistence at #{path}")
        Logger.info("Data will be stored persistently and survive restarts")

      {:error, reason} ->
        Logger.error("Instance #{name}: Invalid data_dir: #{reason}")
        {:stop, {:invalid_config, :data_dir}}
    end

    Logger.info("Instance #{name}: Port #{port}, Database: #{database}")

    children = [
      # Each instance gets its own Go port
      {PgliteEx.Bridge.PortBridge,
       [
         name: bridge_name(name),
         wasm_path: wasm_path,
         data_dir: data_dir,
         username: username,
         database: database,
         debug: debug
       ]},

      # Each instance gets its own socket server
      {PgliteEx.SocketServer,
       [
         name: server_name(name),
         bridge: bridge_name(name),
         port: port,
         host: host,
         debug: debug
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Registry helpers

  defp via_tuple(name), do: {:via, Registry, {PgliteEx.Registry, {:instance, name}}}
  defp bridge_name(name), do: {:via, Registry, {PgliteEx.Registry, {:bridge, name}}}
  defp server_name(name), do: {:via, Registry, {PgliteEx.Registry, {:server, name}}}

  @doc """
  Parse and validate data directory configuration.

  Returns one of:
  - `{:memory, nil}` - In-memory storage (ephemeral)
  - `{:file, path}` - File-based persistence
  - `{:error, reason}` - Invalid configuration

  ## Examples

      iex> PgliteEx.Instance.parse_data_dir("memory://")
      {:memory, nil}

      iex> PgliteEx.Instance.parse_data_dir("./data/mydb")
      {:file, "./data/mydb"}

      iex> PgliteEx.Instance.parse_data_dir("file:///tmp/db")
      {:file, "/tmp/db"}

      iex> PgliteEx.Instance.parse_data_dir("")
      {:memory, nil}
  """
  def parse_data_dir(data_dir) when is_binary(data_dir) do
    cond do
      # Empty string or memory:// protocol means in-memory
      is_memory_mode?(data_dir) ->
        {:memory, nil}

      # file:// protocol prefix
      String.starts_with?(data_dir, @file_protocol) ->
        path = String.slice(data_dir, String.length(@file_protocol)..-1//1)
        validate_file_path(path)

      # Plain path (relative or absolute)
      true ->
        validate_file_path(data_dir)
    end
  end

  def parse_data_dir(_), do: {:error, "data_dir must be a string"}

  # Private helpers for data directory parsing

  defp is_memory_mode?(data_dir) do
    data_dir == "" or String.starts_with?(data_dir, @memory_protocol)
  end

  defp validate_file_path(""), do: {:error, "file path cannot be empty"}

  defp validate_file_path(path) when is_binary(path) do
    # Basic validation - ensure it's not just whitespace
    if String.trim(path) == "" do
      {:error, "file path cannot be blank"}
    else
      {:file, path}
    end
  end
end
