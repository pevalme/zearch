#!/bin/bash
#
# Description: Install all tools required to build zearch and run its benchmarks.
#
# Installs:
#   - Build tools: gcc, make
#   - libfa (via libaugeas-dev) – NFA library required to compile zearch
#   - Compression tools: zstd, lz4, gzip, ncompress
#   - Search baselines: ripgrep, grep
#   - Data tools: wget, unzip, iconv, m4, python3, pip
#   - Python library: requests (for download_gdrive.py)
#   - Re-Pair compressor (built from source – not available in apt)

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
# 4. Build zearch
# ---------------------------------------------------------------------------

ZEARCH_DIR="$(dirname "$SCRIPT_DIR")"

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
echo "  zearch   : $ZEARCH_DIR/zearch"
echo "  repair   : $REPAIR_DIR/repair"
echo "  despair  : $REPAIR_DIR/despair"
echo "============================================================"
