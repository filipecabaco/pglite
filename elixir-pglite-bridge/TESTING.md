# Testing Guide

This document describes the testing strategy for PGliteEx and how to run the tests.

## Test Categories

### Unit Tests

**Location:** `test/pglite_ex/instance_test.exs`, `test/pglite_ex/protocol/messages_test.exs`

**What they test:**
- Pure functions and logic
- Configuration parsing
- Data validation
- Protocol message construction

**Dependencies:**
- None (no external dependencies)

**Run:**
```bash
mix test
```

**Example:**
```elixir
test "parses memory:// as in-memory mode" do
  assert {:memory, nil} = Instance.parse_data_dir("memory://")
end
```

### Integration Tests

**Location:** `test/pglite_ex/integration_test.exs`

**What they test:**
- Full system end-to-end functionality
- Multi-instance lifecycle (start, stop, list)
- Instance isolation
- Persistence modes (memory and file)
- Configuration options
- Error handling
- Registry integration

**Dependencies:**
- Go port must be built (`cd pglite_port && make install`)
- PGlite WASM files in `priv/pglite/`
- Sufficient system resources for multiple instances

**Run:**
```bash
# Run all tests including integration tests
mix test --include integration

# Run only integration tests
mix test --only integration
```

**Note:** Integration tests are **skipped by default** because they require the full system to be set up. You'll see a helpful message when running `mix test`:

```
ℹ Integration tests are excluded by default.
  Run with: mix test --include integration
  Requirements: Go port built, WASM files downloaded
```

## Test Organization

```
test/
├── test_helper.exs              # Test configuration
├── pglite_ex_test.exs           # Main API tests
├── pglite_ex/
│   ├── instance_test.exs        # Unit tests for Instance module
│   ├── integration_test.exs     # Integration tests (skipped by default)
│   └── protocol/
│       └── messages_test.exs    # Protocol message tests
```

## Running Tests

### All Unit Tests (Default)

```bash
mix test
```

This runs all tests except those tagged with `:integration` or `:skip`.

### Specific Test File

```bash
mix test test/pglite_ex/instance_test.exs
```

### Specific Test

```bash
mix test test/pglite_ex/instance_test.exs:10
```

### With Coverage

```bash
mix test --cover
```

### Integration Tests Only

```bash
mix test --only integration
```

### Everything Including Integration

```bash
mix test --include integration
```

## Writing Tests

### Unit Tests

Unit tests should be fast, isolated, and test a single unit of functionality.

```elixir
defmodule PgliteEx.MyModuleTest do
  use ExUnit.Case, async: true  # Run in parallel
  doctest PgliteEx.MyModule

  describe "my_function/1" do
    test "handles valid input" do
      assert {:ok, result} = MyModule.my_function(valid_input)
      assert result == expected_value
    end

    test "returns error for invalid input" do
      assert {:error, reason} = MyModule.my_function(invalid_input)
      assert reason == :expected_error
    end
  end
end
```

**Best Practices:**
- Use `async: true` when tests don't share state
- Use `describe` blocks to group related tests
- Test both success and error cases
- Use descriptive test names
- Keep tests simple and focused

### Integration Tests

Integration tests should verify end-to-end functionality.

```elixir
defmodule PgliteEx.MyIntegrationTest do
  use ExUnit.Case, async: false  # Don't run in parallel
  @moduletag :integration         # Tag for selective running

  setup do
    # Start application if needed
    {:ok, _} = Application.ensure_all_started(:pglite_ex)

    # Clean up function runs after each test
    on_exit(fn ->
      # Cleanup code
    end)

    :ok
  end

  @tag :skip  # Skip during development
  test "full workflow" do
    # Test complete functionality
  end
end
```

**Best Practices:**
- Use `async: false` for tests that modify shared state
- Tag with `@moduletag :integration`
- Use `setup` and `on_exit` for proper cleanup
- Tag flaky tests with `:skip` during development
- Test realistic scenarios
- Include timing/sleep calls if needed for async operations

## Test Coverage

Generate coverage report:

```bash
mix test --cover
```

View detailed coverage:

```bash
mix test --cover && open cover/excoveralls.html
```

**Coverage Goals:**
- Overall: >80%
- Core modules (Instance, InstanceSupervisor, Application): >90%
- Protocol handling: >85%
- Examples and scripts: Not required

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Install dependencies
        run: mix deps.get

      - name: Build Go port
        run: cd pglite_port && make install

      - name: Download WASM files
        run: ./scripts/download_wasm.sh

      - name: Run unit tests
        run: mix test

      - name: Run integration tests
        run: mix test --include integration

      - name: Check formatting
        run: mix format --check-formatted

      - name: Run Credo
        run: mix credo --strict
```

## Common Test Patterns

### Testing Instance Lifecycle

```elixir
test "can start and stop instance" do
  {:ok, pid} = PgliteEx.start_instance(:test_db,
    port: 15432,
    data_dir: "memory://"
  )

  assert Process.alive?(pid)
  assert :test_db in PgliteEx.list_instances()

  :ok = PgliteEx.stop_instance(:test_db)
  refute Process.alive?(pid)
  refute :test_db in PgliteEx.list_instances()
end
```

### Testing Error Cases

```elixir
test "returns error for duplicate instance" do
  {:ok, _} = PgliteEx.start_instance(:dup, port: 15432, data_dir: "memory://")

  assert {:error, :already_started} =
    PgliteEx.start_instance(:dup, port: 15433, data_dir: "memory://")

  PgliteEx.stop_instance(:dup)
end
```

### Testing with Postgrex

```elixir
test "can execute queries via Postgrex" do
  {:ok, _} = PgliteEx.start_instance(:query_test,
    port: 15434,
    data_dir: "memory://"
  )

  {:ok, conn} = Postgrex.start_link(
    hostname: "localhost",
    port: 15434,
    username: "postgres",
    database: "postgres"
  )

  {:ok, result} = Postgrex.query(conn, "SELECT 1", [])
  assert [[1]] = result.rows

  GenServer.stop(conn)
  PgliteEx.stop_instance(:query_test)
end
```

### Testing Cleanup

```elixir
setup do
  # Ensure clean state
  PgliteEx.list_instances()
  |> Enum.each(&PgliteEx.stop_instance/1)

  on_exit(fn ->
    # Cleanup after test
    PgliteEx.list_instances()
    |> Enum.each(&PgliteEx.stop_instance/1)
  end)

  :ok
end
```

## Performance Testing

### Benchmarking

Use Benchee for performance testing:

```elixir
# test/benchmarks/query_bench.exs
Benchee.run(%{
  "simple query" => fn ->
    Postgrex.query(conn, "SELECT 1", [])
  end,
  "complex query" => fn ->
    Postgrex.query(conn, "SELECT * FROM large_table LIMIT 100", [])
  end
})
```

Run with:
```bash
mix run test/benchmarks/query_bench.exs
```

### Load Testing

Test multiple concurrent connections:

```elixir
test "handles concurrent connections" do
  {:ok, _} = PgliteEx.start_instance(:load_test,
    port: 15435,
    data_dir: "memory://"
  )

  tasks = Enum.map(1..10, fn i ->
    Task.async(fn ->
      {:ok, conn} = Postgrex.start_link(
        hostname: "localhost",
        port: 15435,
        username: "postgres"
      )

      {:ok, _} = Postgrex.query(conn, "SELECT #{i}", [])
      GenServer.stop(conn)
    end)
  end)

  Enum.each(tasks, &Task.await/1)

  PgliteEx.stop_instance(:load_test)
end
```

## Debugging Tests

### Run with trace

```bash
mix test --trace
```

Shows test execution in real-time with timing.

### Run with IEx

```bash
iex -S mix test
```

Drop into IEx shell after tests complete.

### Debug specific test

```elixir
test "my failing test" do
  require IEx; IEx.pex  # Stops here
  # ... test code
end
```

### Enable debug logging

```elixir
setup do
  Logger.configure(level: :debug)
  on_exit(fn -> Logger.configure(level: :info) end)
  :ok
end
```

## Common Issues

### Integration tests fail with "port not found"

**Solution:** Build the Go port:
```bash
cd pglite_port
make install
```

### Integration tests fail with "WASM file not found"

**Solution:** Download WASM files to `priv/pglite/`

### Tests timeout

**Solution:** Increase timeout:
```elixir
@tag timeout: :infinity
test "long running test" do
  # ...
end
```

### Port already in use

**Solution:** Use different ports in tests:
```elixir
# Use random high port
port = 15000 + :rand.uniform(1000)
```

### Tests fail intermittently

**Solution:**
1. Use `async: false` for tests that share state
2. Add proper cleanup in `on_exit`
3. Add sleep/wait for async operations
4. Check for race conditions

## Test Data Management

### Temporary Directories

```elixir
test "creates persistent database" do
  temp_dir = Path.join(System.tmp_dir(), "test_#{:rand.uniform(10000)}")

  {:ok, _} = PgliteEx.start_instance(:temp_test,
    port: 15436,
    data_dir: temp_dir
  )

  # ... test code

  PgliteEx.stop_instance(:temp_test)
  File.rm_rf(temp_dir)
end
```

### Fixtures

```elixir
# test/support/fixtures.ex
defmodule PgliteEx.Fixtures do
  def sample_users do
    [
      %{name: "Alice", email: "alice@example.com"},
      %{name: "Bob", email: "bob@example.com"}
    ]
  end
end

# In test
alias PgliteEx.Fixtures

test "loads fixture data" do
  Enum.each(Fixtures.sample_users(), fn user ->
    # Insert user
  end)
end
```

## Contributing Tests

When contributing new features:

1. **Add unit tests** for all new functions
2. **Add integration tests** for end-to-end functionality
3. **Update doctests** in module documentation
4. **Ensure all tests pass** before submitting PR
5. **Aim for >80% coverage** for new code

Example PR checklist:
- [ ] Unit tests added
- [ ] Integration tests added (if applicable)
- [ ] Doctests updated
- [ ] All tests pass (`mix test --include integration`)
- [ ] Code formatted (`mix format`)
- [ ] No compiler warnings

## Further Reading

- [ExUnit Documentation](https://hexdocs.pm/ex_unit/)
- [Testing Elixir](https://pragprog.com/titles/lmelixir/testing-elixir/)
- [Property-Based Testing](https://hexdocs.pm/stream_data/)
- [Mocking in Elixir](https://hexdocs.pm/mox/)
