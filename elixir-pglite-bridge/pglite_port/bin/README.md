# Pre-built Binaries

This directory contains pre-built Go binaries for the PGlite port, compiled for different platforms.

## Available Platforms

- **linux-amd64**: Linux x86_64 (most common Linux servers and desktops)
- **linux-arm64**: Linux ARM64 (Raspberry Pi 4+, ARM servers)
- **darwin-amd64**: macOS Intel (older Macs)
- **darwin-arm64**: macOS Apple Silicon (M1/M2/M3 Macs)

## Usage

When you run `mix deps.get` or `mix compile`, the Mix compiler will automatically:

1. Detect your platform
2. Copy the appropriate pre-built binary to `_build/*/lib/pglite_ex/priv/`
3. Fall back to building from source if your platform isn't supported

## Building Binaries

Maintainers can rebuild these binaries using:

```bash
cd pglite_port
./build_release.sh
```

This will:
- Build binaries for all supported platforms
- Create checksums for verification
- Place binaries in the correct directory structure

## Checksums

See `checksums.txt` for SHA256 checksums of all binaries.

## Platform Not Supported?

If your platform isn't listed here, the library will attempt to build from source.
Requirements:
- Go 1.19 or later
- Standard build tools (gcc/clang)

To request a new platform, please open an issue on GitHub with:
- Your OS (from `uname -s`)
- Your architecture (from `uname -m`)
- Output from `go env GOOS GOARCH`
