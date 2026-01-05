.PHONY: build test clean install deps

# Build the Go port
build:
	go build -ldflags="-s -w" -o pglite-port main.go

# Build and install to Elixir priv directory
install: build
	mkdir -p ../priv
	cp pglite-port ../priv/
	chmod +x ../priv/pglite-port

# Download dependencies
deps:
	go mod download
	go mod tidy

# Run tests
test:
	go test -v ./...

# Clean build artifacts
clean:
	rm -f pglite-port
	rm -f ../priv/pglite-port

# Build for multiple platforms
build-all:
	GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o pglite-port-linux-amd64 main.go
	GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o pglite-port-linux-arm64 main.go
	GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o pglite-port-darwin-amd64 main.go
	GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o pglite-port-darwin-arm64 main.go

# Format code
fmt:
	go fmt ./...

# Lint
lint:
	golangci-lint run

# Run in development mode
run:
	go run main.go
