# CLAUDE.md — Developer Guide for AI Assistants

## Project Overview

**zearch** is a regular expression engine that searches directly on grammar-compressed text
without decompression. It implements the algorithm described in:

> *"Regular Expression Matching on Compressed Text"*
> Pierre Ganty & Pedro Valero, IMDEA Software Institute
> Data Compression Conference (DCC) 2019
> DOI: [10.1109/DCC.2019.00061](https://doi.org/10.1109/DCC.2019.00061)
> Paper: `main.pdf` in the repository root

The core insight: for each grammar variable, compute the NFA state-transition update
that processing that variable's expansion would produce. Then compose updates
bottom-up through the grammar rules. This runs in O(p·s³·log N) time where p is the
compressed size, s is the NFA state count, and N is the uncompressed text length —
often exponentially faster than decompress-then-search.

---

## Repository Layout

```
zearch/
├── src/                   # All C source code
│   ├── main.c             # Entry point, top-level search logic, match expansion
│   ├── types.h            # Shared type definitions (TRANSITION_FULL, TRANSITION_SEQ, etc.)
│   ├── nfa.h / nfa.c      # NFA data structure + saturation construction
│   ├── count.h / count.c  # Line-counting logic per grammar variable
│   ├── simd.h / simd.c    # SSE2 SIMD acceleration for the saturation construction
│   ├── memory.h / memory.c# Custom allocator for NFA edge (PAIR) storage
│   ├── stack.h / stack.c  # Resizable integer stack (used to parse grammar from file)
│   └── bitin.h / bitin.c  # Bit-level file reader (Re-Pair compressed format)
├── benchmark/
│   ├── install_tools.sh   # Installs all dependencies and builds zearch end-to-end
│   ├── generate_files.sh  # Downloads datasets and produces compressed test files
│   ├── download_gdrive.py # Helper: download large files from Google Drive
│   └── extract_books.sh   # Concatenates Project Gutenberg text files
├── graphs/                # Pre-computed benchmark results (JSON) + graph templates
│   ├── *.json             # Timing data per dataset/size (list of {Regex, tool: {avg,err}})
│   ├── *_cactus.json      # Data formatted for cactus plots
│   ├── generate_table.sh  # Generates HTML table from JSON files
│   ├── script_cactus.txt  # SVG/D3.js template for cactus plots
│   └── graphs_full.tar.gz / graphs_web.tar.gz  # Archives of generated HTML graphs
├── main.pdf               # Conference paper (full algorithm explanation)
├── Makefile               # Build system
├── README.md              # User-facing documentation
└── LICENSE.txt            # GPL v3
```

---

## Algorithm Summary (from the paper)

### Core Concept: Straight Line Programs (SLPs)

zearch operates on **grammar-compressed text** (Straight Line Programs). A SLP is a
context-free grammar generating exactly one string — the original text. Each rule has
the form `X → Y Z` (binary). Re-Pair is the compressor used to generate `.rp` files.

### Saturation Construction

For each grammar variable X with rule `X → A B`, the algorithm computes:
- The set of NFA state pairs `(q₁, q₂)` such that reading X's expansion transitions
  the NFA from q₁ to q₂.
- This is done by **composing** the transition relations of A and B:
  if A can go from q₁ to qₘ, and B can go from qₘ to q₂, then X goes from q₁ to q₂.

The SIMD module accelerates this relation composition using SSE2 intrinsics.

### Counting

`TRANSITION_FULL` tracks per-variable:
- `count`: number of fully-contained matching lines
- `left`: whether the leftmost newline has a match to its left
- `right`: whether the rightmost newline has a match to its right
- `new_lines`: whether the variable generates at least one newline
- `match`: whether the single-line expansion of this variable matches

`TRANSITION_SEQ` is a smaller struct used for the "axiom sequence" (the top-level
sequence of grammar symbols that together form the full text).

### Operating Modes

| Flag | Behavior |
|------|----------|
| `-c` | Print count of matching lines only (fastest; uses `run_zearch` count path) |
| `-l` | Print matching lines only |
| `-a` | Print both count and matching lines |
| `-b` | Boolean: print MATCH or DOES NOT MATCH (uses `run_boolean_zearch`) |

Optional `-m` flag: minimize the NFA after construction (via `fa_minimize`). Does not
always improve performance.

### Input File Format (Re-Pair `.rp`)

Binary format written by `repair`:
1. `uint32`: uncompressed text length
2. `uint32`: number of grammar rules
3. `uint32`: sequence length (axiom length)
4. Bit-packed grammar tree (read via `bitin.c`): balanced-parenthesis encoding of the
   parse tree, where each leaf is a variable index encoded in
   `32 - __builtin_clz(rules_counter)` bits.

---

## Key Data Structures

### `TRANSITION_FULL` (src/types.h:42)
Core NFA state per grammar variable. Stores edge pairs inline (`initial[]`/`final[]`
arrays of size `NUM_PAIRS_INITIAL=4`) and overflows into the `MEMORY` allocator.

### `TRANSITION_SEQ` (src/types.h:57)
Compact version for axiom processing: only tracks `new_lines`, `match`, `left`, `right`.

### `MEMORY` (src/memory.h)
A custom block allocator for `PAIR` structs (pairs of NFA states). Uses short-typed
(block, index) pointers instead of raw pointers to save memory. Blocks are
`BLOCKS_LENGTH=1` PAIRs each. Pre-allocates `MAX_PREALLOCATED=32768` entries.

### `SIMD_SYMBOL` (src/simd.h)
SSE2-based data structure for accelerating the relation composition step. Stores
transitions in 128-bit registers (8 × 16-bit state IDs per register) for vectorized
lookup.

### Constants (src/types.h)
| Constant | Value | Meaning |
|----------|-------|---------|
| `MAX_REGEX_SIZE` | 1024 | Max NFA states |
| `ALPHABET_SIZE` | 256 | ASCII alphabet |
| `COUNTER_TOP` | 33554432 (2²⁵) | Max lines counted before overflow |
| `MATCH_MAX_LENGTH` | 1000 | Output buffer size for match lines |
| `CHAR_SIZE` | 256 | Terminal symbols (maps to ASCII) |

---

## Build System

### Prerequisites

| Tool | Purpose | Install (Ubuntu/Debian) |
|------|---------|------------------------|
| `gcc` (≥ 4.8) | Compiler | `apt-get install gcc` |
| `libfa` / `libaugeas-dev` | NFA/regex library | `apt-get install libaugeas-dev` |
| `zstd` | Benchmark baseline compression | `apt-get install zstd` |
| `lz4` | Benchmark baseline compression | `apt-get install lz4` |
| `grep` / `rg` | Benchmark baseline search | `apt-get install ripgrep` |
| `libhyperscan-dev` | Benchmark baseline (Hyperscan) | `apt-get install libhyperscan-dev` |
| `repair` | Compress files for zearch input | Build from source (see below) |

### Building Re-Pair (required to create `.rp` test files)

```bash
wget https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz
tar xzf repair110811.tar.gz
cd repair110811
make
sudo cp repair despair /usr/local/bin/
```

### Building zearch

```bash
make zearch        # Optimized binary
make debug         # With -DDEBUG: verbose stderr output
make stats         # With -DSTATS: JSON memory/performance statistics to stdout
make plot          # With -DPLOT: CSV output per rule for plotting
make clean         # Remove built binaries
```

**Important Makefile notes:**

- The Makefile uses `CC ?= gcc` (overridable). The original code required `gcc-8`
  because newer gcc (≥ 10) defaults to `-fno-common`, which rejects the global
  variables (`mem`, `expand`) declared directly in header files (`memory.h`,
  `count.h`). The current Makefile adds `-fcommon` to re-enable the old behavior.
- `-flto` is intentionally omitted. LTO with `-fcommon` causes link-time multiple
  definition errors on modern gcc.
- The `zearch`, `debug`, `stats`, and `plot` targets compile all `.c` files together
  in one `gcc` invocation (rather than separate `.o` compilation + link). This is
  required because `make` cannot reliably override `CC` for the implicit `.c → .o`
  rule while also using `-fcommon` properly with LTO.

To override build settings:

```bash
make CC=gcc-12 CFLAGS="-O2 -fcommon" LFLAGS="-L/usr/local/lib -lfa" zearch
```

If `libfa` is installed to a non-standard location (e.g., from a custom augeas build):

```bash
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
make LFLAGS="-L/usr/local/lib -lfa" zearch
```

---

## Usage

```
./zearch [-m] <option> <regex> <input.rp>
./debug  [-m] <option> <regex> <input.rp>
./stats  [-m] <option> <regex> <input.rp>
```

Examples:

```bash
# Compress a file
repair myfile.txt          # produces myfile.txt.rp

# Count matching lines
./zearch -c "hello.*world" myfile.txt.rp

# Print matching lines
./zearch -l "error|warning" logfile.txt.rp

# Count + print
./zearch -a "GET /api/" access.log.rp

# Boolean existence check
./zearch -b "^admin" users.txt.rp

# With NFA minimization (sometimes faster for complex regexes)
./zearch -m -c "pattern" input.rp
```

Regex syntax follows libfa/augeas conventions (similar to POSIX ERE, but no
backreferences, no named character classes, ASCII only).

---

## Benchmark Workflow

### Installing All Tools

`benchmark/install_tools.sh` installs all dependencies and builds all binaries in
one step. It must be run from the `benchmark/` directory:

```bash
cd benchmark
bash install_tools.sh
```

This installs system packages via `apt-get`, builds Re-Pair from source into
`benchmark/repair110811/`, builds `graphs/hyperscan`, and then builds `zearch`.
No manual path editing is required — all tool paths in the benchmark scripts are
pre-configured for this repo layout.

### Generating Test Files

`benchmark/generate_files.sh` downloads real-world datasets (NASA web logs,
OpenSubtitles, Project Gutenberg books, Google N-grams, CSV data) and produces
compressed files (`.rp`, `.zst`, `.lz4`, `.gz`, `.Z`) at sizes from 1KB to 500MB.
Run it from the `benchmark/` directory. It requires ~12 GB of disk space.

```bash
cd benchmark
bash generate_files.sh           # full run (all sizes up to 500MB)
bash generate_files.sh --quick   # quick run (sizes up to 100KB only, for testing)
```

The script prompts before downloading. The first prompt downloads the main
datasets (logs, subtitles, Gutenberg — included in all benchmarks). A second
prompt downloads the optional extra datasets (JSON, CSV, qwerty).

**Known issues fixed in the current script:**

- `GENERATE_RANDOM` (not `RANDOM`) controls whether random datasets are generated.
  `RANDOM` is a bash built-in PRNG variable; assigning to it just seeds the
  generator. The variable is named `GENERATE_RANDOM` to avoid this conflict.
- CSV dataset: the five Google N-grams `.gz` files are each decompressed
  individually through a per-file loop rather than passing all files to a single
  `zcat`. Passing multiple files to `zcat` while `head -c` limits downstream output
  causes the pipeline to produce empty output (silent SIGPIPE interaction).
  Each file is piped as `zcat file | iconv | head -c <remaining>` and appended,
  stopping when 1 GB is accumulated.
- Random/RandomL datasets: `head -c 524288000` is used instead of
  `dd bs=10M count=50 iflags=fullblock`, which was unreliable on slow pipes.

### Running Benchmarks and Generating Graphs

`graphs/generate_graphs.sh` runs all benchmarks, writes timing results as JSON
files in `graphs/`, and produces `graphs/index.html` with embedded D3.js charts.
Run it from the `graphs/` directory:

```bash
cd graphs
bash generate_graphs.sh                       # all file types, all sizes
bash generate_graphs.sh --small               # sizes up to 1MB only
bash generate_graphs.sh --types logs,subs     # specific file types only
bash generate_graphs.sh --small --types csv   # combine flags
```

Available `--types` values: `subs`, `gutenberg`, `csv`, `logs`, `qwerty`, `all`.

`graphs/generate_table.sh` is an alternative that runs a smaller fixed benchmark
(files up to 100KB) and also records compression ratios and decompression speeds:

```bash
cd graphs
bash generate_table.sh
```

Both scripts expect:
- `../zearch` at the project root
- `../benchmark/repair110811/repair` and `despair`
- `../benchmark/{logs,subs,gutenberg,...}/original*.txt` from `generate_files.sh`
- `./hyperscan` in the `graphs/` directory

The JSON result format is:
```json
[
  {
    "Regex": "r1",
    "zearch": {"avg": 2.567, "err": 0.18},
    "zgrep_lz4_p": {"avg": 2.867, "err": 0.124},
    ...
    "MatchesZ": 95,
    "MatchesGG": 95
  }
]
```

Each file is named `{SIZE}{DATASET}.json` (e.g., `100KBLogs.json`) or
`{SIZE}{DATASET}_cactus.json` for cactus-plot format. The live version of the
pre-computed results is at
[pevalme.github.io/zearch/graphs/index.html](https://pevalme.github.io/zearch/graphs/index.html).

---

## Known Limitations

1. **No cross-line matches** — a regex match must be contained within a single line.
2. **No invert match** (`grep -v` equivalent).
3. **Regular languages only** — no backreferences, lookahead, or other non-regular
   features (equivalent to RE2).
4. **No zero-width assertions** — no `^`, `$`, `\b`, etc.
5. **No named character classes** — no `[:alpha:]`, `[:digit:]`, etc.
6. **ASCII only** — no UTF-8.
7. **No highlighted output** — only full matching lines are printed.
8. **Max 1024 NFA states** (`MAX_REGEX_SIZE`) — very complex regexes may hit this.
9. **Max ~33.5 million lines counted** before overflow (handled via `counting_overflows`
   counter that tracks multiples of `COUNTER_TOP`).

---

## Code Conventions

- **Language**: C (C99 compatible, though some headers rely on `-fcommon` behavior).
- **Build target**: x86_64 with SSE2 (`-march=native`). The SIMD module uses
  `emmintrin.h` (SSE2 intrinsics). Non-x86 platforms are not supported.
- **Global variables**: Key state is held in globals in `main.c` (`grammar`,
  `automaton`, `automaton_seq`, `edges`, etc.). `mem` (MEMORY) and `expand` (bool)
  are defined in headers and shared across translation units — this requires
  `-fcommon` on gcc ≥ 10.
- **Compile-time modes**: Controlled by preprocessor flags (`-DDEBUG`, `-DSTATS`,
  `-DPLOT`). Do not mix these flags in one binary.
- **Debug output**: All debug prints go to `stderr` via the `DEBUG_PRINT` macro.
  Stats output goes to `stdout` as JSON.
- **Memory alignment**: `posix_memalign(..., 64, ...)` is used for all major arrays
  to ensure cache-line alignment for SIMD performance.
- **Error handling**: Minimal — most errors call `exit(-1)`.
- **Authors**: Pedro Valero & Pierre Ganty, IMDEA Software Institute (2018).
  License: GPL v3.

---

## Debugging and Profiling

```bash
# Verbose debug output (writes to stderr)
./debug -c "pattern" input.rp 2>&1 | less

# Memory/performance statistics (JSON on stdout)
./stats -c "pattern" input.rp

# Plot mode: emits CSV of per-rule edge counts to stdout
./plot -c "pattern" input.rp > edges.csv
```

The `-m` flag (NFA minimization) can be combined with any mode and sometimes
improves performance for regexes with many states.

---

## Quick Verification

After building, verify the toolchain end-to-end:

```bash
# Create and compress a test file
echo -e "hello world\nfoo bar\nhello universe\nbaz qux" > test.txt
repair test.txt             # produces test.txt.rp

# Search with zearch
./zearch -c "hello" test.txt.rp   # should print: 2
./zearch -l "hello" test.txt.rp   # should print the two matching lines
./zearch -b "hello" test.txt.rp   # should print: MATCH
./zearch -b "zzz"   test.txt.rp   # should print: DOES NOT MATCH

# Verify against grep baseline
grep -c "hello" test.txt           # should also print: 2
```

---

## Dependency Reference

| Dependency | Source | Role |
|------------|--------|------|
| [augeas/libfa](https://github.com/hercules-team/augeas) | augeas project | Regex → NFA conversion. `fa_compile()`, `fa_minimize()`, `fa_state_*()` APIs |
| [Re-Pair](https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz) | Larsson & Moffat (2000) | Grammar-based compressor; produces `.rp` files |
| SSE2 (`emmintrin.h`) | x86 CPU | SIMD acceleration for saturation construction |
| zstd / lz4 / gzip | Standard tools | Benchmark baselines only (not used by zearch itself) |
| grep / ripgrep / hyperscan | Standard tools | Benchmark baselines only |
