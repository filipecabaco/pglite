defmodule Mix.Tasks.Compile.Pglite do
  @moduledoc """
  Ensures PGlite dependencies are ready before compilation.

  This compiler task:
  1. Detects the platform (OS and architecture)
  2. Downloads PGlite WASM files if not present
  3. Uses pre-built Go binary if available for the platform
  4. Falls back to building from source if Go is installed

  Runs automatically during `mix deps.compile` or `mix compile`.
  """

  use Mix.Task.Compiler
  require Logger

  @recursive true

  @impl Mix.Task.Compiler
  def run(_args) do
    Mix.shell().info("==> Preparing PGlite dependencies...")

    with :ok <- ensure_priv_directory(),
         :ok <- ensure_wasm_files(),
         :ok <- ensure_go_binary() do
      Mix.shell().info("==> PGlite dependencies ready!")
      {:ok, []}
    else
      {:error, reason} ->
        Mix.shell().error("Failed to prepare PGlite: #{reason}")
        {:error, []}
    end
  end

  @impl Mix.Task.Compiler
  def clean do
    # Don't remove downloaded files on clean
    # Users can manually remove priv/ if needed
    :ok
  end

  ## Private functions

  defp ensure_priv_directory do
    priv_dir = priv_path()

    unless File.exists?(priv_dir) do
      File.mkdir_p!(priv_dir)
    end

    pglite_dir = Path.join(priv_dir, "pglite")

    unless File.exists?(pglite_dir) do
      File.mkdir_p!(pglite_dir)
    end

    :ok
  end

  defp ensure_wasm_files do
    wasm_file = Path.join([priv_path(), "pglite", "pglite.wasm"])

    if File.exists?(wasm_file) do
      Mix.shell().info("  ✓ PGlite WASM files found")
      :ok
    else
      Mix.shell().info("  ⚙ Downloading PGlite WASM files...")
      download_wasm_files()
    end
  end

  defp download_wasm_files do
    # PGlite WASM download URL (from @electric-sql/pglite npm package)
    # Version: 0.1.5 (update as needed)
    version = "0.1.5"

    base_url =
      "https://cdn.jsdelivr.net/npm/@electric-sql/pglite@#{version}/dist/postgres.wasm"

    wasm_dest = Path.join([priv_path(), "pglite", "pglite.wasm"])

    case download_file(base_url, wasm_dest) do
      :ok ->
        Mix.shell().info("  ✓ Downloaded PGlite WASM files")
        :ok

      {:error, reason} ->
        Mix.shell().error("""
          Failed to download PGlite WASM files: #{inspect(reason)}

          Please download manually:
            1. Visit: https://www.npmjs.com/package/@electric-sql/pglite
            2. Extract postgres.wasm from dist/ directory
            3. Copy to: #{wasm_dest}

          Or use npm:
            npm install @electric-sql/pglite
            cp node_modules/@electric-sql/pglite/dist/postgres.wasm #{wasm_dest}
        """)

        {:error, "WASM download failed"}
    end
  end

  defp ensure_go_binary do
    binary_name = "pglite-port"
    binary_path = Path.join(priv_path(), binary_name)

    if File.exists?(binary_path) do
      Mix.shell().info("  ✓ Go port binary found")
      :ok
    else
      Mix.shell().info("  ⚙ Preparing Go port binary...")
      prepare_go_binary(binary_path)
    end
  end

  defp prepare_go_binary(binary_path) do
    platform = detect_platform()

    Mix.shell().info("  Platform detected: #{platform}")

    # Try to use pre-built binary first
    prebuilt_path = Path.join(["pglite_port", "bin", platform, "pglite-port"])

    cond do
      File.exists?(prebuilt_path) ->
        Mix.shell().info("  ✓ Using pre-built binary for #{platform}")
        File.cp!(prebuilt_path, binary_path)
        File.chmod!(binary_path, 0o755)
        :ok

      go_installed?() ->
        Mix.shell().info("  ⚙ Building Go binary from source...")
        build_go_binary(binary_path)

      true ->
        Mix.shell().error("""
          No pre-built binary for #{platform} and Go is not installed.

          Please either:
            1. Install Go (https://go.dev/doc/install) and run: mix compile
            2. Build on a supported platform and copy the binary to:
               #{binary_path}

          Supported pre-built platforms:
            - linux-amd64
            - linux-arm64
            - darwin-amd64
            - darwin-arm64
        """)

        {:error, "Go binary not available"}
    end
  end

  defp build_go_binary(binary_path) do
    go_dir = "pglite_port"

    unless File.exists?(go_dir) do
      {:error, "pglite_port directory not found"}
    else
      # Build the Go binary
      case System.cmd("go", ["build", "-o", Path.expand(binary_path), "main.go"],
             cd: go_dir,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          Mix.shell().info("  ✓ Built Go binary successfully")
          File.chmod!(binary_path, 0o755)
          :ok

        {output, _} ->
          Mix.shell().error("Go build failed: #{output}")
          {:error, "Go build failed"}
      end
    end
  end

  defp detect_platform do
    os =
      case :os.type() do
        {:unix, :linux} -> "linux"
        {:unix, :darwin} -> "darwin"
        {:unix, :freebsd} -> "freebsd"
        _ -> "unknown"
      end

    arch =
      case :erlang.system_info(:system_architecture) do
        arch when is_list(arch) ->
          arch_str = List.to_string(arch)

          cond do
            String.contains?(arch_str, "x86_64") -> "amd64"
            String.contains?(arch_str, "aarch64") -> "arm64"
            String.contains?(arch_str, "arm64") -> "arm64"
            String.contains?(arch_str, "i686") -> "386"
            String.contains?(arch_str, "i386") -> "386"
            true -> "unknown"
          end
      end

    "#{os}-#{arch}"
  end

  defp go_installed? do
    case System.cmd("which", ["go"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp download_file(url, dest) do
    # Try curl first, then wget
    cond do
      System.find_executable("curl") ->
        case System.cmd("curl", ["-fSL", "-o", dest, url], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, _} -> {:error, output}
        end

      System.find_executable("wget") ->
        case System.cmd("wget", ["-O", dest, url], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, _} -> {:error, output}
        end

      true ->
        {:error, "Neither curl nor wget found"}
    end
  end

  defp priv_path do
    Path.join(Mix.Project.app_path(), "priv")
  end
end
