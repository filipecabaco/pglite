defmodule PgliteEx.Application do
  @moduledoc """
  The PgliteEx Application.

  Starts the supervision tree that manages the PGlite WASM bridge
  and the PostgreSQL wire protocol socket server.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting PgliteEx application...")

    # Get configuration
    config = Application.get_all_env(:pglite_ex)
    wasm_path = Keyword.get(config, :wasm_path, "priv/pglite/pglite.wasm")
    socket_port = Keyword.get(config, :socket_port, 5432)
    socket_host = Keyword.get(config, :socket_host, "127.0.0.1")
    data_dir = Keyword.get(config, :data_dir, "memory://")
    username = Keyword.get(config, :username, "postgres")
    database = Keyword.get(config, :database, "postgres")
    debug = Keyword.get(config, :debug, 0)
    multi_instance = Keyword.get(config, :multi_instance, false)

    children =
      if multi_instance do
        Logger.info("Starting in multi-instance mode")
        build_multi_instance_children()
      else
        Logger.info("Starting in single-instance mode (default instance)")
        build_single_instance_children(
          wasm_path: wasm_path,
          socket_port: socket_port,
          socket_host: socket_host,
          data_dir: data_dir,
          username: username,
          database: database,
          debug: debug
        )
      end

    opts = [strategy: :one_for_one, name: PgliteEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Multi-instance mode: Registry + DynamicSupervisor for managing multiple instances
  defp build_multi_instance_children do
    [
      # Registry for named instance lookup
      {Registry, keys: :unique, name: PgliteEx.Registry},

      # Dynamic supervisor for managing multiple instances
      PgliteEx.InstanceSupervisor
    ]
  end

  # Single-instance mode: Start one default instance (backward compatible)
  defp build_single_instance_children(opts) do
    wasm_path = Keyword.fetch!(opts, :wasm_path)
    socket_port = Keyword.fetch!(opts, :socket_port)
    socket_host = Keyword.fetch!(opts, :socket_host)
    data_dir = Keyword.fetch!(opts, :data_dir)
    username = Keyword.fetch!(opts, :username)
    database = Keyword.fetch!(opts, :database)
    debug = Keyword.fetch!(opts, :debug)

    [
      # Registry for named instance lookup (needed for Instance supervisor)
      {Registry, keys: :unique, name: PgliteEx.Registry},

      # Start a single default instance
      {PgliteEx.Instance,
       [
         name: :default,
         config: [
           port: socket_port,
           host: socket_host,
           data_dir: data_dir,
           username: username,
           database: database,
           debug: debug,
           wasm_path: wasm_path
         ]
       ]}
    ]
  end
end
