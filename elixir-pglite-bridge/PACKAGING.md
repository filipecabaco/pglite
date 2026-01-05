# Packaging and Distribution Guide

This document explains how PGliteEx is packaged and distributed to ensure users can install it as a Git dependency without manual setup steps.

## Overview

PGliteEx has two external dependencies:

1. **PGlite WASM files** (~15MB) - The PostgreSQL WASM binary
2. **Go port binary** (~10MB) - The Go program that runs the WASM

Our packaging strategy ensures both are automatically available when users install the library.

## How It Works

### For Users (Installing the Library)

When a user adds PGliteEx as a dependency:

```elixir
# mix.exs
def deps do
  [
    {:pglite_ex, github: "your-org/pglite-elixir-bridge"}
  ]
end
```

And runs `mix deps.get`:

1. **Mix downloads** the repository
2. **Mix compiler runs** `Mix.Tasks.Compile.Pglite` automatically
3. The compiler:
   - Detects the platform (OS + architecture)
   - Downloads PGlite WASM if not present
   - Uses pre-built Go binary if available for their platform
   - Falls back to building from source if needed
4. User can immediately run `iex -S mix` and use PGliteEx

**No manual steps required!**

## For Maintainers (Releasing)

### Building Pre-Built Binaries

Before each release, build binaries for all supported platforms:

```bash
cd pglite_port
./build_release.sh
```

This creates binaries in `pglite_port/bin/`:

```
bin/
├── linux-amd64/
│   └── pglite-port
├── linux-arm64/
│   └── pglite-port
├── darwin-amd64/
│   └── pglite-port
├── darwin-arm64/
│   └── pglite-port
└── checksums.txt
```

### Committing Binaries

```bash
git add pglite_port/bin/
git commit -m "chore: Update pre-built binaries for vX.Y.Z"
git push
```

**Note:** Yes, we commit binaries to the repository. This is intentional to ensure zero-setup installation for users.

### Testing on Target Platforms

Before releasing, test each binary:

```bash
# On each platform
./pglite_port/bin/<platform>/pglite-port < test_input.txt
```

### Git Attributes

The `.gitattributes` file ensures binaries are handled correctly:

```
# Pre-built binaries
pglite_port/bin/**/* binary
*.wasm binary

# Don't diff binaries
pglite_port/bin/**/* -diff
*.wasm -diff
```

## Architecture

### Platform Detection

The Mix compiler detects the platform using Erlang system info:

```elixir
def detect_platform do
  os = case :os.type() do
    {:unix, :linux} -> "linux"
    {:unix, :darwin} -> "darwin"
    ...
  end

  arch = case :erlang.system_info(:system_architecture) do
    # Parse architecture string
    ...
  end

  "#{os}-#{arch}"  # e.g., "linux-amd64"
end
```

### Binary Selection Priority

1. **Pre-built binary** (fastest, no dependencies)
   - Check `pglite_port/bin/<platform>/pglite-port`
   - If exists, copy to `priv/pglite-port`

2. **Build from source** (requires Go)
   - Run `go build` in `pglite_port/`
   - Place result in `priv/pglite-port`

3. **Fail with helpful message**
   - Tell user to install Go or use supported platform

### WASM File Handling

WASM files are downloaded from CDN on first compile:

```elixir
# Source: @electric-sql/pglite npm package
url = "https://cdn.jsdelivr.net/npm/@electric-sql/pglite@#{version}/dist/postgres.wasm"
dest = "priv/pglite/pglite.wasm"

# Download using curl or wget
download_file(url, dest)
```

**Why download vs commit?**
- WASM files are large (~15MB compressed)
- They change with PGlite updates
- CDN is reliable and fast
- Reduces repository size

## Supported Platforms

### Officially Supported (Pre-Built)

- **Linux x86_64** (linux-amd64)
  - Ubuntu 20.04+, Debian 11+, RHEL 8+, etc.
  - Most cloud servers (AWS, GCP, Azure)

- **Linux ARM64** (linux-arm64)
  - Raspberry Pi 4+
  - ARM-based cloud instances (AWS Graviton, etc.)

- **macOS Intel** (darwin-amd64)
  - macOS 10.15+ on Intel processors

- **macOS Apple Silicon** (darwin-arm64)
  - macOS 11+ on M1/M2/M3 chips

### Build from Source Platforms

Any Unix platform with Go 1.19+ can build from source:
- FreeBSD
- OpenBSD
- Other architectures (386, mips64, etc.)

### Not Supported

- **Windows**: Not currently supported
  - Would require significant changes to port communication
  - Open to contributions!

## File Sizes

Typical installation sizes:

| Component | Uncompressed | Compressed (git) |
|-----------|--------------|------------------|
| Go binary (single) | ~10MB | ~3MB |
| All Go binaries (4) | ~40MB | ~12MB |
| WASM files | ~15MB | ~5MB |
| **Total** | ~55MB | ~17MB |

**Repository size impact:** Adding pre-built binaries increases repo size by ~12MB, but provides zero-setup experience for 95% of users.

## Troubleshooting

### "No pre-built binary for X platform"

**Solution 1:** Install Go and rebuild:
```bash
curl -OL https://go.dev/dl/go1.21.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
mix deps.clean pglite_ex --build
mix deps.compile pglite_ex
```

**Solution 2:** Request platform support by opening an issue.

### "Failed to download WASM files"

**Solution 1:** Manual download:
```bash
mkdir -p priv/pglite
curl -L -o priv/pglite/pglite.wasm \
  https://cdn.jsdelivr.net/npm/@electric-sql/pglite@0.1.5/dist/postgres.wasm
```

**Solution 2:** Use npm to get files:
```bash
npm install @electric-sql/pglite
cp node_modules/@electric-sql/pglite/dist/postgres.wasm priv/pglite/
```

### "Go build failed"

Check Go version:
```bash
go version  # Should be 1.19+
```

Check dependencies:
```bash
cd pglite_port
go mod tidy
go build main.go
```

### Binary permission denied

```bash
chmod +x priv/pglite-port
```

## Publishing to Hex.pm (Future)

When ready to publish to Hex.pm, considerations:

### Package Size Limits

Hex.pm has a **256MB uncompressed** package size limit. Our package would be ~55MB, well within the limit.

### Hex Package Structure

```
lib/
  mix/tasks/compile/pglite.ex
  pglite_ex/
priv/
  pglite-port  (included in package)
  pglite/
    pglite.wasm  (included in package)
pglite_port/
  bin/  (all pre-built binaries included)
```

### mix.exs Changes

```elixir
defp package do
  [
    name: "pglite_ex",
    files: ~w(
      lib
      priv
      pglite_port/bin
      mix.exs
      README.md
      ARCHITECTURE.md
      LICENSE
    ),
    licenses: ["Apache-2.0"],
    links: %{"GitHub" => "https://github.com/..."}
  ]
end
```

### Build Process

For Hex, we would:
1. Include all pre-built binaries in the package
2. Include WASM files in `priv/pglite/`
3. Remove download logic (everything is local)
4. Compiler just copies files to build directory

## Git Dependency vs Hex.pm

### Git Dependency (Current)

**Pros:**
- Bleeding edge features
- Easy to contribute
- Can reference specific commits

**Cons:**
- Requires git installed
- Downloads full repository history
- ~17MB download (with binaries)

**Setup:**
```elixir
{:pglite_ex, github: "org/repo"}
```

### Hex.pm (Future)

**Pros:**
- Faster installation (package server)
- Version management
- Dependency resolution
- Trusted package ecosystem

**Cons:**
- Must publish new versions
- Larger package size (~55MB)

**Setup:**
```elixir
{:pglite_ex, "~> 0.1"}
```

## Continuous Integration

### GitHub Actions Example

Build and test on all platforms:

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, macos-13]
        include:
          - os: ubuntu-latest
            platform: linux-amd64
          - os: macos-latest
            platform: darwin-arm64
          - os: macos-13
            platform: darwin-amd64

    runs-on: ${{ matrix.os }}

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

      - name: Compile (this will build/download dependencies)
        run: mix compile

      - name: Verify binary works
        run: |
          echo "SELECT 1" | _build/dev/lib/pglite_ex/priv/pglite-port
```

### Automated Binary Builds

Use GitHub Actions to build binaries on release:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-binaries:
    # Build for all platforms
    # Upload as release artifacts
    # Optionally commit back to repo
```

## Security Considerations

### Binary Trust

Users install binaries from the repository. To ensure trust:

1. **Checksums:** `checksums.txt` allows verification
2. **Signed commits:** Use GPG-signed commits for releases
3. **Reproducible builds:** Document exact build environment
4. **Source available:** Users can always build from source

### WASM Download

WASM files downloaded from CDN:

1. **HTTPS only:** Always use secure connections
2. **Checksum verification:** Verify downloaded files (TODO)
3. **Version pinning:** Lock to specific PGlite version
4. **Fallback:** Allow local WASM files

## Versioning Strategy

### PGlite Version Coupling

PGliteEx version numbers map to PGlite versions:

```
PgliteEx 0.1.x -> PGlite 0.1.5
PgliteEx 0.2.x -> PGlite 0.2.0
```

### Breaking Changes

- Major version bump: Breaking Elixir API changes
- Minor version bump: New features, PGlite updates
- Patch version bump: Bug fixes, documentation

## Development Workflow

### For Contributors

```bash
# Clone the repository
git clone https://github.com/org/pglite-elixir-bridge.git
cd pglite-elixir-bridge

# Install dependencies (will auto-build)
mix deps.get
mix compile

# Run tests
mix test

# Build binaries for all platforms (maintainers only)
cd pglite_port
./build_release.sh
```

### For Maintainers

Before each release:

1. Update version in `mix.exs`
2. Update CHANGELOG.md
3. Build fresh binaries: `cd pglite_port && ./build_release.sh`
4. Commit binaries: `git add pglite_port/bin && git commit -m "chore: Update binaries for vX.Y.Z"`
5. Tag release: `git tag vX.Y.Z`
6. Push: `git push && git push --tags`

## Future Improvements

1. **WASM Checksums:** Verify downloaded WASM files
2. **Binary Signatures:** Sign binaries with GPG
3. **Caching:** Cache downloaded files in user's home directory
4. **Windows Support:** Port communication on Windows
5. **Hex.pm Publishing:** Make available on official package manager
6. **Pre-compilation:** Use `elixir_make` for better build integration
7. **Musl builds:** Static binaries for Alpine Linux

## Questions?

- **Why commit binaries?** Zero-setup experience for users
- **Why not Hex.pm?** Will publish when stable (v1.0)
- **Why download WASM?** Too large to commit (~15MB)
- **What about security?** All binaries built from source (see `build_release.sh`)

## Additional Resources

- [Elixir Make](https://github.com/elixir-lang/elixir_make) - Alternative build system
- [Hex Package Building](https://hex.pm/docs/publish) - Publishing to Hex
- [GitHub Packages](https://github.com/features/packages) - Alternative package hosting
