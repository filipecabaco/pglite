defmodule PgliteEx do
  @moduledoc """
  PGliteEx - Elixir bridge to PGlite WebAssembly

  This module provides the main API for interacting with PGlite from Elixir.
  """

  alias PgliteEx.Bridge

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
    Bridge.exec_protocol_raw(message)
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
    case Process.whereis(Bridge) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end
end
