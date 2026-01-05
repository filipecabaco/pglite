defmodule PgliteEx.InstanceTest do
  use ExUnit.Case, async: false
  doctest PgliteEx.Instance

  alias PgliteEx.Instance

  describe "parse_data_dir/1" do
    test "parses memory:// as in-memory mode" do
      assert {:memory, nil} = Instance.parse_data_dir("memory://")
    end

    test "parses empty string as in-memory mode" do
      assert {:memory, nil} = Instance.parse_data_dir("")
    end

    test "parses file:// prefix correctly" do
      assert {:file, "/tmp/db"} = Instance.parse_data_dir("file:///tmp/db")
      assert {:file, "data/mydb"} = Instance.parse_data_dir("file://data/mydb")
    end

    test "parses plain paths as file paths" do
      assert {:file, "./data/mydb"} = Instance.parse_data_dir("./data/mydb")
      assert {:file, "/tmp/postgres"} = Instance.parse_data_dir("/tmp/postgres")
      assert {:file, "data"} = Instance.parse_data_dir("data")
    end

    test "validates empty file paths" do
      assert {:error, "file path cannot be empty"} = Instance.parse_data_dir("file://")
    end

    test "validates blank file paths" do
      assert {:error, "file path cannot be blank"} = Instance.parse_data_dir("file://   ")
      assert {:error, "file path cannot be blank"} = Instance.parse_data_dir("   ")
    end

    test "validates non-string input" do
      assert {:error, "data_dir must be a string"} = Instance.parse_data_dir(nil)
      assert {:error, "data_dir must be a string"} = Instance.parse_data_dir(123)
      assert {:error, "data_dir must be a string"} = Instance.parse_data_dir(:atom)
    end
  end
end
