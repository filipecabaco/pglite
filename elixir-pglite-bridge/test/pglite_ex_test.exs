defmodule PgliteExTest do
  use ExUnit.Case
  doctest PgliteEx

  test "version returns a version string" do
    {:ok, version} = PgliteEx.version()
    assert is_binary(version)
    assert String.contains?(version, "PGlite")
  end

  test "ready? returns boolean" do
    result = PgliteEx.ready?()
    assert is_boolean(result)
  end
end
