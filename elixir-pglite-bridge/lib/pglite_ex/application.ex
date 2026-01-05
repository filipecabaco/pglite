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
    debug = Keyword.get(config, :debug, 0)

    children = [
      # Start the PGlite WASM bridge
      {PgliteEx.Bridge,
       [
         wasm_path: wasm_path,
         debug: debug
       ]},

      # Start the PostgreSQL wire protocol socket server
      {PgliteEx.SocketServer,
       [
         port: socket_port,
         host: socket_host,
         debug: debug
       ]}
    ]

    opts = [strategy: :one_for_one, name: PgliteEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
