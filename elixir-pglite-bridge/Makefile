.PHONY: help build build-go build-elixir test clean install setup

# Show help by default
help:
	@echo "PGliteEx Build Commands:"
	@echo ""
	@echo "  make setup        - Initial setup (download WASM, build Go port)"
	@echo "  make build        - Build both Go port and Elixir app"
	@echo "  make build-go     - Build only the Go port"
	@echo "  make build-elixir - Build only the Elixir app"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make run          - Start the application"
	@echo ""

# Initial setup
setup: download-wasm build-go
	@echo "Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. mix deps.get"
	@echo "  2. make build"
	@echo "  3. make run"

# Download PGlite WASM files from NPM
download-wasm:
	@echo "Downloading PGlite WASM files..."
	@mkdir -p priv/pglite
	@cd priv/pglite && \
		npm pack @electric-sql/pglite && \
		tar -xzf electric-sql-pglite-*.tgz && \
		cp package/dist/pglite.wasm ./ && \
		cp package/dist/pglite.data ./ && \
		rm -rf package *.tgz
	@echo "WASM files downloaded to priv/pglite/"

# Build everything
build: build-go build-elixir

# Build Go port
build-go:
	@echo "Building Go port..."
	@cd pglite_port && make install

# Build Elixir application
build-elixir:
	@echo "Building Elixir application..."
	@mix deps.get
	@mix compile

# Run tests
test: test-go test-elixir

test-go:
	@cd pglite_port && make test

test-elixir:
	@mix test

# Clean artifacts
clean: clean-go clean-elixir

clean-go:
	@cd pglite_port && make clean

clean-elixir:
	@mix clean
	@rm -rf _build

# Run the application
run:
	@iex -S mix

# Format code
fmt:
	@mix format
	@cd pglite_port && make fmt
