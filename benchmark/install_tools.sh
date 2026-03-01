#!/bin/bash
#
# Description: Install all tools required to build zearch and run its benchmarks.
#
# Installs:
#   - Build tools: gcc, make
#   - libfa (via libaugeas-dev) – NFA library required to compile zearch
#   - Compression tools: zstd, lz4, gzip, ncompress
#   - Search baselines: ripgrep, grep, libhyperscan-dev
#   - Data tools: wget, unzip, m4, python3, pip
#   - Python library: requests (for download_gdrive.py)
#   - Re-Pair compressor (built from source – not available in apt)
#   - graphs/hyperscan binary (built from source using libhyperscan)

set -euo pipefail

BLUE="\033[0;34m"
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------

info "Installing system packages via apt-get..."

if ! command -v apt-get &>/dev/null; then
    error "apt-get not found. Please install the packages listed in this script manually."
fi

sudo apt-get update -qq

sudo apt-get install -y \
    gcc \
    make \
    libaugeas-dev \
    libhyperscan-dev \
    zstd \
    lz4 \
    gzip \
    ncompress \
    ripgrep \
    wget \
    unzip \
    m4 \
    python3 \
    python3-pip

ok "System packages installed."

# ---------------------------------------------------------------------------
# 2. Python library: requests
# ---------------------------------------------------------------------------

info "Installing Python 'requests' library..."
pip3 install --user --quiet requests
ok "Python requests installed."

# ---------------------------------------------------------------------------
# 3. Re-Pair compressor (built from source)
#    The benchmark scripts expect the 'repair' and 'despair' binaries.
#    We place the build next to the benchmark/ directory so that the relative
#    paths used in generate_files.sh and generate_graphs.sh remain consistent
#    with the rest of the project layout.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZEARCH_DIR="$(dirname "$SCRIPT_DIR")"
REPAIR_URL="https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz"
REPAIR_ARCHIVE="repair110811.tar.gz"
REPAIR_DIR="$SCRIPT_DIR/repair110811"

if [[ -x "$REPAIR_DIR/repair" && -x "$REPAIR_DIR/despair" ]]; then
    ok "Re-Pair binaries already present at $REPAIR_DIR – skipping build."
else
    info "Downloading Re-Pair source..."
    wget -q -O "/tmp/$REPAIR_ARCHIVE" "$REPAIR_URL"

    info "Extracting Re-Pair source..."
    tar -xzf "/tmp/$REPAIR_ARCHIVE" -C "$SCRIPT_DIR"
    rm "/tmp/$REPAIR_ARCHIVE"

    info "Building Re-Pair..."
    make -C "$REPAIR_DIR" -s

    if [[ -x "$REPAIR_DIR/repair" && -x "$REPAIR_DIR/despair" ]]; then
        ok "Re-Pair built successfully: $REPAIR_DIR/repair"
    else
        error "Re-Pair build failed. Check the output above for details."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Build graphs/hyperscan – line-counting Hyperscan baseline binary
# ---------------------------------------------------------------------------

HYPERSCAN_SRC="$ZEARCH_DIR/graphs/hyperscan.c"
HYPERSCAN_BIN="$ZEARCH_DIR/graphs/hyperscan"

if [[ -x "$HYPERSCAN_BIN" ]]; then
    ok "graphs/hyperscan already built – skipping."
else
    info "Building graphs/hyperscan..."
    gcc -O2 -o "$HYPERSCAN_BIN" "$HYPERSCAN_SRC" -lhs

    if [[ -x "$HYPERSCAN_BIN" ]]; then
        ok "graphs/hyperscan built successfully."
    else
        error "graphs/hyperscan build failed. Check the output above for details."
    fi
fi

# ---------------------------------------------------------------------------
# 5. Build zearch
# ---------------------------------------------------------------------------

info "Building zearch..."
make -C "$ZEARCH_DIR" -s zearch

if [[ -x "$ZEARCH_DIR/zearch" ]]; then
    ok "zearch built successfully: $ZEARCH_DIR/zearch"
else
    error "zearch build failed. Check the output above for details."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
ok "All tools installed successfully."
echo "  zearch     : $ZEARCH_DIR/zearch"
echo "  repair     : $REPAIR_DIR/repair"
echo "  despair    : $REPAIR_DIR/despair"
echo "  hyperscan  : $ZEARCH_DIR/graphs/hyperscan"
echo "============================================================"
