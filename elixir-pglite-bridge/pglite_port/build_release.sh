#!/usr/bin/env bash

# Build cross-platform binaries for PGlite Go port
#
# This script builds binaries for common Unix platforms that users might use.
# Run this script as a maintainer when preparing a release.
#
# Requirements:
#   - Go 1.19+
#   - Cross-compilation support (usually included with Go)
#
# Usage:
#   ./build_release.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PGlite Go Port - Cross-Platform Build ===${NC}\n"

# Platforms to build for
PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "darwin/amd64"
    "darwin/arm64"
)

# Output directory
OUTPUT_DIR="bin"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo "Please install Go from https://go.dev/doc/install"
    exit 1
fi

echo "Go version: $(go version)"
echo ""

# Ensure dependencies are downloaded
echo "Downloading Go dependencies..."
go mod download
echo ""

# Build for each platform
for platform in "${PLATFORMS[@]}"; do
    # Split platform into OS and ARCH
    IFS='/' read -r GOOS GOARCH <<< "$platform"

    # Output filename
    output_name="$OUTPUT_DIR/$GOOS-$GOARCH/pglite-port"

    echo -e "${YELLOW}Building for $GOOS/$GOARCH...${NC}"

    # Create platform directory
    mkdir -p "$(dirname "$output_name")"

    # Build
    if GOOS=$GOOS GOARCH=$GOARCH go build -o "$output_name" \
        -ldflags="-s -w" \
        -trimpath \
        main.go; then

        # Make executable
        chmod +x "$output_name"

        # Get file size
        size=$(du -h "$output_name" | cut -f1)

        echo -e "${GREEN}✓ Built: $output_name ($size)${NC}"
    else
        echo -e "${RED}✗ Failed to build for $GOOS/$GOARCH${NC}"
        exit 1
    fi

    echo ""
done

echo -e "${GREEN}=== Build Complete ===${NC}\n"
echo "Binaries created in: $OUTPUT_DIR/"
echo ""
ls -lh "$OUTPUT_DIR"/**/pglite-port
echo ""

# Create checksums
echo "Creating checksums..."
cd "$OUTPUT_DIR"
find . -name "pglite-port" -type f -exec sha256sum {} \; > checksums.txt
cd - > /dev/null
echo -e "${GREEN}✓ Checksums saved to: $OUTPUT_DIR/checksums.txt${NC}"
echo ""

echo -e "${GREEN}Next steps:${NC}"
echo "1. Test each binary on its target platform"
echo "2. Commit the binaries to the repository:"
echo "   git add pglite_port/bin/"
echo "   git commit -m 'chore: Update pre-built binaries'"
echo "3. Users will automatically use these binaries when installing"
