#!/bin/bash
# Benchmark: Rust zearch-rs vs C zearch
# Generates test files at various sizes, measures wall-clock time for -c and -b modes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZEARCH_C="$SCRIPT_DIR/../zearch"
ZEARCH_RS="$SCRIPT_DIR/../zearch-rs/target/release/zearch-rs"
REPAIR="$SCRIPT_DIR/repair110811/repair"
TMPDIR_BM="$(mktemp -d)"

BLUE="\033[0;34m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; NC="\033[0m"

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
head_() { echo -e "${YELLOW}$*${NC}"; }

PATTERNS=("hello" "error" "hello.*world" "foo.bar" "[a-z]*")
REPS=5

cleanup() { rm -rf "$TMPDIR_BM"; }
trap cleanup EXIT

# ── Generate test corpora ──────────────────────────────────────────────────────

info "Generating test corpora in $TMPDIR_BM ..."

python3 -c "
import random, sys
words = ['hello', 'world', 'foo', 'bar', 'error', 'warning', 'info', 'debug',
         'test', 'data', 'log', 'search', 'match', 'text', 'line', 'file']
tmpdir = sys.argv[1]
for size_label, n_lines in [('10K', 500), ('100K', 5000), ('500K', 25000), ('1M', 50000), ('5M', 250000), ('10M', 500000)]:
    lines = [' '.join(random.choices(words, k=random.randint(3,10))) for _ in range(n_lines)]
    text = '\n'.join(lines) + '\n'
    path = f'{tmpdir}/{size_label}.txt'
    with open(path, 'w') as f:
        f.write(text)
    print(f'  wrote {path}: {len(text)} bytes, {n_lines} lines', flush=True)
" "$TMPDIR_BM"

info "Compressing with Re-Pair ..."
for label in 10K 100K 500K 1M 5M 10M; do
    "$REPAIR" "$TMPDIR_BM/${label}.txt" 2>/dev/null
    info "  ${label}.txt.rp done"
done

# ── Timing helper ──────────────────────────────────────────────────────────────

# measure_time <cmd> <args...>  → prints mean wall-clock seconds over REPS runs
measure_time() {
    local total=0
    local i
    for i in $(seq 1 "$REPS"); do
        local t
        t=$( { /usr/bin/time -f "%e" "$@" > /dev/null 2>&1; } 2>&1 || \
             { time "$@" > /dev/null 2>&1; } 2>&1 | grep real | \
             awk '{gsub("m","*60+"); gsub("s",""); print}' | bc -l )
        # Try /usr/bin/time -f "%e" which gives seconds directly
        total=$(echo "$total + $t" | bc -l)
    done
    echo "scale=4; $total / $REPS" | bc -l
}

# Simpler timing using bash TIMEFORMAT
time_secs() {
    local total=0
    local i t
    for i in $(seq 1 "$REPS"); do
        t=$( TIMEFORMAT='%R'; { time "$@" > /dev/null 2>&1; } 2>&1 )
        total=$(echo "$total + $t" | bc -l)
    done
    printf "%.4f" "$(echo "scale=4; $total / $REPS" | bc -l)"
}

# ── Run benchmarks ─────────────────────────────────────────────────────────────

printf "\n"
head_ "============================================================"
head_ " Benchmark: C zearch vs Rust zearch-rs   [mode: -c]"
head_ " Repetitions: $REPS"
head_ "============================================================"
printf "\n"
printf "%-8s  %-20s  %10s  %10s  %10s\n" "SIZE" "PATTERN" "C (s)" "Rust (s)" "Speedup"
printf "%-8s  %-20s  %10s  %10s  %10s\n" "--------" "--------------------" "----------" "----------" "----------"

for label in 10K 100K 500K 1M 5M 10M; do
    rp="$TMPDIR_BM/${label}.txt.rp"
    for pat in "${PATTERNS[@]}"; do
        c_t=$(time_secs "$ZEARCH_C" -c "$pat" "$rp")
        rs_t=$(time_secs "$ZEARCH_RS" -c "$pat" "$rp")
        # Compute speedup: how many times faster is Rust vs C (>1 = Rust faster)
        speedup=$(printf "%.2f" "$(echo "scale=4; $c_t / $rs_t" | bc -l 2>/dev/null || echo 1)")
        printf "%-8s  %-20s  %10s  %10s  %9sx\n" "$label" "$pat" "$c_t" "$rs_t" "$speedup"
    done
    echo ""
done

head_ "============================================================"
head_ " Boolean mode (-b): short-circuits on first match"
head_ "============================================================"
printf "\n"
printf "%-8s  %-20s  %10s  %10s  %10s\n" "SIZE" "PATTERN" "C (s)" "Rust (s)" "Speedup"
printf "%-8s  %-20s  %10s  %10s  %10s\n" "--------" "--------------------" "----------" "----------" "----------"

for label in 10K 100K 500K 1M 5M 10M; do
    rp="$TMPDIR_BM/${label}.txt.rp"
    for pat in "hello" "zzzzzzzzz"; do
        c_t=$(time_secs "$ZEARCH_C" -b "$pat" "$rp")
        rs_t=$(time_secs "$ZEARCH_RS" -b "$pat" "$rp")
        speedup=$(printf "%.2f" "$(echo "scale=4; $c_t / $rs_t" | bc -l 2>/dev/null || echo 1)")
        printf "%-8s  %-20s  %10s  %10s  %9sx\n" "$label" "$pat" "$c_t" "$rs_t" "$speedup"
    done
    echo ""
done

ok "Benchmark complete."
