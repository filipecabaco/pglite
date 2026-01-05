# Exclude integration tests by default
# Run with: mix test --include integration
ExUnit.start(exclude: [:integration, :skip])

# Print helpful message about integration tests
if "--include" not in System.argv() do
  IO.puts("\n" <> IO.ANSI.yellow() <> "ℹ Integration tests are excluded by default." <> IO.ANSI.reset())
  IO.puts(IO.ANSI.yellow() <> "  Run with: mix test --include integration" <> IO.ANSI.reset())
  IO.puts(IO.ANSI.yellow() <> "  Requirements: Go port built, WASM files downloaded\n" <> IO.ANSI.reset())
end
