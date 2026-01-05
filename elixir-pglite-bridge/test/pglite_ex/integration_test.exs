defmodule PgliteEx.IntegrationTest do
  use ExUnit.Case, async: false

  # These tests require the Go port to be built and WASM file to be present
  # Skip them if dependencies are not available
  @moduletag :integration

  alias PgliteEx.InstanceSupervisor

  setup do
    # Ensure we're in multi-instance mode for these tests
    # Start the application if not already started
    case Application.ensure_all_started(:pglite_ex) do
      {:ok, _} -> :ok
      {:error, {:already_started, :pglite_ex}} -> :ok
    end

    # Clean up any existing instances
    PgliteEx.list_instances()
    |> Enum.each(&PgliteEx.stop_instance/1)

    :ok
  end

  describe "multi-instance lifecycle" do
    @tag :skip
    test "can start and stop multiple instances" do
      # Start first instance
      assert {:ok, pid1} =
               PgliteEx.start_instance(:test_db1,
                 port: 15432,
                 data_dir: "memory://"
               )

      assert Process.alive?(pid1)

      # Start second instance on different port
      assert {:ok, pid2} =
               PgliteEx.start_instance(:test_db2,
                 port: 15433,
                 data_dir: "memory://"
               )

      assert Process.alive?(pid2)

      # Both should be in the instance list
      instances = PgliteEx.list_instances()
      assert :test_db1 in instances
      assert :test_db2 in instances

      # Stop first instance
      assert :ok = PgliteEx.stop_instance(:test_db1)
      refute Process.alive?(pid1)

      # Only second instance should remain
      instances = PgliteEx.list_instances()
      refute :test_db1 in instances
      assert :test_db2 in instances

      # Stop second instance
      assert :ok = PgliteEx.stop_instance(:test_db2)
      refute Process.alive?(pid2)

      # No instances should remain
      assert [] = PgliteEx.list_instances()
    end

    @tag :skip
    test "prevents duplicate instance names" do
      # Start first instance
      assert {:ok, _pid} =
               PgliteEx.start_instance(:duplicate_test,
                 port: 15434,
                 data_dir: "memory://"
               )

      # Try to start another with the same name
      assert {:error, :already_started} =
               PgliteEx.start_instance(:duplicate_test,
                 port: 15435,
                 data_dir: "memory://"
               )

      # Clean up
      PgliteEx.stop_instance(:duplicate_test)
    end

    @tag :skip
    test "requires port in configuration" do
      assert {:error, :port_required} =
               PgliteEx.start_instance(:no_port_test,
                 data_dir: "memory://"
               )
    end

    @tag :skip
    test "can get instance information" do
      assert {:ok, pid} =
               PgliteEx.start_instance(:info_test,
                 port: 15436,
                 data_dir: "memory://"
               )

      assert {:ok, info} = PgliteEx.instance_info(:info_test)
      assert info.name == :info_test
      assert info.pid == pid
      assert info.running == true

      # Clean up
      PgliteEx.stop_instance(:info_test)

      # After stopping, info should not be found
      assert {:error, :not_found} = PgliteEx.instance_info(:info_test)
    end
  end

  describe "instance isolation" do
    @tag :skip
    test "instances run on different ports independently" do
      # Start two instances
      assert {:ok, _} =
               PgliteEx.start_instance(:isolated1,
                 port: 15437,
                 data_dir: "memory://"
               )

      assert {:ok, _} =
               PgliteEx.start_instance(:isolated2,
                 port: 15438,
                 data_dir: "memory://"
               )

      # Both should be running
      assert {:ok, info1} = PgliteEx.instance_info(:isolated1)
      assert {:ok, info2} = PgliteEx.instance_info(:isolated2)

      assert info1.running
      assert info2.running

      # Different processes
      assert info1.pid != info2.pid

      # Clean up
      PgliteEx.stop_instance(:isolated1)
      PgliteEx.stop_instance(:isolated2)
    end
  end

  describe "persistence modes" do
    @tag :skip
    test "accepts memory:// data directory" do
      assert {:ok, _} =
               PgliteEx.start_instance(:memory_test,
                 port: 15439,
                 data_dir: "memory://"
               )

      PgliteEx.stop_instance(:memory_test)
    end

    @tag :skip
    test "accepts file path data directory" do
      # Use a temporary directory
      temp_dir = System.tmp_dir!() |> Path.join("pglite_test_#{:rand.uniform(10000)}")

      assert {:ok, _} =
               PgliteEx.start_instance(:file_test,
                 port: 15440,
                 data_dir: temp_dir
               )

      # Directory should be created by the Go port
      # (We can't easily verify this without accessing the filesystem)

      PgliteEx.stop_instance(:file_test)

      # Clean up temp directory
      File.rm_rf(temp_dir)
    end

    @tag :skip
    test "accepts file:// prefixed paths" do
      temp_dir = System.tmp_dir!() |> Path.join("pglite_test_#{:rand.uniform(10000)}")

      assert {:ok, _} =
               PgliteEx.start_instance(:file_prefix_test,
                 port: 15441,
                 data_dir: "file://#{temp_dir}"
               )

      PgliteEx.stop_instance(:file_prefix_test)
      File.rm_rf(temp_dir)
    end
  end

  describe "configuration options" do
    @tag :skip
    test "accepts custom host configuration" do
      assert {:ok, _} =
               PgliteEx.start_instance(:host_test,
                 port: 15442,
                 host: "127.0.0.1",
                 data_dir: "memory://"
               )

      PgliteEx.stop_instance(:host_test)
    end

    @tag :skip
    test "accepts custom username and database" do
      assert {:ok, _} =
               PgliteEx.start_instance(:custom_db_test,
                 port: 15443,
                 username: "admin",
                 database: "testdb",
                 data_dir: "memory://"
               )

      PgliteEx.stop_instance(:custom_db_test)
    end

    @tag :skip
    test "accepts debug level" do
      assert {:ok, _} =
               PgliteEx.start_instance(:debug_test,
                 port: 15444,
                 debug: 1,
                 data_dir: "memory://"
               )

      PgliteEx.stop_instance(:debug_test)
    end
  end

  describe "error handling" do
    @tag :skip
    test "returns error for non-existent instance" do
      assert {:error, :not_found} = PgliteEx.stop_instance(:does_not_exist)
      assert {:error, :not_found} = PgliteEx.instance_info(:does_not_exist)
    end

    @tag :skip
    test "handles port already in use gracefully" do
      # Start first instance
      assert {:ok, _} =
               PgliteEx.start_instance(:port_conflict1,
                 port: 15445,
                 data_dir: "memory://"
               )

      # Try to start second on same port - this should fail during startup
      # The exact error depends on the socket server implementation
      result =
        PgliteEx.start_instance(:port_conflict2,
          port: 15445,
          data_dir: "memory://"
        )

      # Should either fail immediately or the instance should crash
      case result do
        {:error, _reason} -> :ok
        {:ok, pid} -> refute Process.alive?(pid)
      end

      # Clean up
      PgliteEx.stop_instance(:port_conflict1)
    end
  end

  describe "Registry integration" do
    @tag :skip
    test "instances are registered in Registry" do
      assert {:ok, _} =
               PgliteEx.start_instance(:registry_test,
                 port: 15446,
                 data_dir: "memory://"
               )

      # Should be able to lookup via Registry
      assert [{_pid, _}] = Registry.lookup(PgliteEx.Registry, {:instance, :registry_test})
      assert [{_pid, _}] = Registry.lookup(PgliteEx.Registry, {:bridge, :registry_test})
      assert [{_pid, _}] = Registry.lookup(PgliteEx.Registry, {:server, :registry_test})

      PgliteEx.stop_instance(:registry_test)

      # After stopping, should not be in Registry
      assert [] = Registry.lookup(PgliteEx.Registry, {:instance, :registry_test})
    end
  end
end
