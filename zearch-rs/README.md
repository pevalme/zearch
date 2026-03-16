# zearch-rs

Rust reimplementation of [zearch](../) — regular expression matching on
Re-Pair grammar-compressed text (Ganty & Valero, DCC 2019).

## Building

```bash
cargo build --release
# binary: target/release/zearch-rs
```

The `.cargo/config.toml` sets `-C target-cpu=native` automatically.

## Usage

Identical CLI to the C version:

```bash
./target/release/zearch-rs -c "hello.*world" input.rp   # count matching lines
./target/release/zearch-rs -l "error"        input.rp   # print matching lines
./target/release/zearch-rs -a "GET /api"     input.rp   # count + print
./target/release/zearch-rs -b "pattern"      input.rp   # MATCH / DOES NOT MATCH
./target/release/zearch-rs -m -c "pattern"  input.rp   # with NFA minimization
```

## Performance vs C

Benchmarks run with the scripts in `../benchmark/`. Three dataset types
(synthetic logs, Gutenberg-style prose, subtitle-style dialogue) at sizes
from 100 KB to 500 MB, using the eight regex patterns from
`../graphs/generate_table.sh` (r1–r8). The word-corpus benchmark
(`bench_rs_vs_c.sh`) covers an additional set of simple patterns.

All timings are 5-repetition averages of wall-clock time (`-c` count mode).
Machine: x86_64, both binaries built with `-O3 -march=native`.

### Count mode (`-c`) — Rust speedup over C

| File size | Simple patterns (`what`, `HTTP`, `.`) | Complex patterns (`[a-z]{4}`, date regex) |
|-----------|--------------------------------------|------------------------------------------|
| ≤ 1 MB    | 0.95–1.18× (tied, startup-dominated) | 0.85–1.07×                               |
| 5 MB      | 1.02–1.10×                           | 1.00–1.09×                               |
| 10 MB     | 1.02–1.18×                           | 1.00–1.11×                               |
| 500 MB    | **1.04–1.15×**                       | 0.92–1.02×                               |

Representative 500 MB numbers (dataset / pattern / C time → Rust time):

| Dataset    | Pattern              | C (s) | Rust (s) | Speedup |
|------------|----------------------|-------|----------|---------|
| logs       | `.` (any line)       | 0.727 | 0.632    | **+15%** |
| logs       | `what`               | 0.723 | 0.673    | **+7%**  |
| logs       | `HTTP`               | 0.693 | 0.666    | **+4%**  |
| gutenberg  | `.`                  | 1.199 | 1.074    | **+12%** |
| gutenberg  | `what`               | 1.254 | 1.190    | **+5%**  |
| gutenberg  | `[0-9]{4}`           | 1.112 | 1.027    | **+8%**  |
| subtitles  | `what`               | 2.022 | 1.790    | **+13%** |
| subtitles  | date regex           | 1.646 | 1.483    | **+11%** |
| subtitles  | `[a-z]*[a-z]{3}`     | 2.431 | 2.387    | **+2%**  |
| word corpus | `[a-z]*`            | 0.915 | 0.822    | **+11%** |
| word corpus | `foo.bar`           | 0.878 | 0.816    | **+8%**  |
| gutenberg  | `I .* you`           | 1.391 | 1.521    | **−9%**  |
| gutenberg  | `[a-z]*[a-z]{3}`     | 1.587 | 1.725    | **−9%**  |

Rust wins consistently on patterns that produce small NFAs (≤ ~10 states).
The two losses are on Gutenberg with patterns that generate larger NFAs
(`I .* you`, `[a-z]*[a-z]{3}`): more NFA states means more work per bitrow
word, and the Rust implementation's advantage from tighter cache usage shrinks.

### Boolean mode (`-b`) — early exit

C wins here at all sizes for patterns that match early (e.g., `-b hello` on a
file where matches are common). At 500 MB C takes ~32 ms vs. Rust ~94 ms.
The search exits on the very first grammar rule that matches, so the total
runtime is dominated by Re-Pair file parsing and binary startup overhead
(~0.6 ms extra for Rust), not the search algorithm itself.

For patterns with no matches (`-b zzzzzzzzz`), the full grammar must be
traversed, and both implementations are neck-and-neck:

| Size  | C (s) | Rust (s) | Speedup |
|-------|-------|----------|---------|
| 10 M  | 0.029 | 0.028    | +5%     |
| 500 M | 0.739 | 0.692    | +7%     |

### Why Rust is faster at large scale

Four algorithmic differences from the C version, all applied after the NFA
state count is known:

1. **Compact `recently_added` dedup table** — resized from
   `MAX_REGEX_SIZE × MAX_REGEX_SIZE × 4 = 4 MB` to `num_states² × 4` bytes
   (typically ~400 bytes for a 10-state NFA). The whole table fits in L1 cache
   instead of thrashing L2/L3 on every saturation step.

2. **Bitrow scratch buffer** — replaces the C version's `edges[1024][1024]`
   (2 MB) + `num_edges[1024]` array with a `num_states × ⌈num_states/64⌉`
   u64 bitset (~80 bytes for a 10-state NFA). Composition iterates set bits
   with `trailing_zeros` + `bits &= bits−1` rather than scanning a dense
   index array.

3. **Deferred allocation** — `recently_added`, `scratch_bitrow`, and
   `reached_states` are not allocated at startup; they are created in
   `resize_after_automaton_init()` after `fa_compile()` returns. This avoids
   zero-filling 4+ MB at startup for every invocation.

4. **LTO thin + `target-cpu=native`** — enables cross-function inlining and
   full use of AVX2/SSE4.2 where the compiler chooses to auto-vectorise.

## Implementation notes

The Rust code is a faithful port of the C algorithm with no semantic
differences. It shares the same `libfa` (augeas) FFI for regex-to-NFA
compilation. Unsafe indexing (`get_unchecked`) is used in the two inner
loops of `add_rule` (the saturation construction) where bounds are
statically guaranteed by construction.

The `TransitionFull` struct is bit-packed to exactly 16 bytes, matching the
C bitfield layout:

```
[initial: 4 B][final_: 4 B][first_block: 2 B][first_index: 2 B][packed: 4 B]
packed = count(25b) | new_lines(1b) | is_there(1b) | match_(1b) | right(1b) | left(1b) | pairs_used(2b)
```
