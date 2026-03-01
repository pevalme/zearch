# Regular Expression Search on Compressed Text

**zearch** is a regular expression engine that takes a regular expression and a grammar-compressed text file and returns every line of the uncompressed text containing a match.

**zearch** implements the algorithm presented at the Data Compression Conference (DCC) in 2019. A link to the article is given [here](https://doi.org/10.1109/DCC.2019.00061).

## Limitations

- no match across lines
- no support for invert match option
- only regular languages (like RE2) — e.g. no backreferences
- no zero-width characters
- no named character classes (e.g. alnum, digit, lower, …)
- no UTF-8 support, only ASCII characters
- no highlighted output, only matching lines are reported in full

## Compiling

### Quick Start: Install All Tools

The `benchmark/install_tools.sh` script installs all dependencies and builds zearch in one step. It installs:

- Build tools: `gcc`, `make`
- `libaugeas-dev` — NFA library required to compile zearch
- Compression tools: `zstd`, `lz4`, `gzip`, `ncompress`
- Search baselines: `ripgrep`, `grep`, `libhyperscan-dev`
- Data tools: `wget`, `unzip`, `m4`, `python3`, `pip`, `requests`
- Re-Pair compressor (built from source at `benchmark/repair110811/`)
- `graphs/hyperscan` binary (built from source)
- `zearch` binary (built from the project root)

```bash
cd benchmark
bash install_tools.sh
```

After the script completes, `zearch` is ready to use from the project root.

### Manual Installation

#### Installing libfa

Install the tools and libraries required to build **augeas**:

```bash
sudo apt-get install bison flex libreadline-dev libxml2-dev
```

Clone the [augeas project](https://github.com/hercules-team/augeas) repository:

```bash
git clone git@github.com:hercules-team/augeas.git
```

From the augeas root folder run:

```bash
./autogen.sh
make
sudo make install
```

Update the library path so that **zearch** can find **libfa**:

```bash
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
```

#### Installing Re-Pair

Re-Pair is the compressor used to produce `.rp` input files for zearch. It must be built from source:

```bash
wget https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz
tar xzf repair110811.tar.gz -C benchmark/
make -C benchmark/repair110811
```

#### Compiling Zearch

From the root folder of this repository run `make zearch stats debug`, which generates three executables:

- `zearch` — the main program
- `stats` — works like zearch but prints memory usage statistics (JSON on stdout)
- `debug` — prints verbose debugging information to stderr

These three tools are invoked the same way:

```
./{zearch,debug,stats} [-m] <option> <input_regex> <input_file>
```

where:
- `-m` is optional. When present, the NFA is determinized and minimized after construction. This does not always improve performance.
- `option` can be `-c`, `-l`, `-a`, or `-b` to print the number of matching lines, the matching lines, both, or simply whether at least one match exists.
- `input_regex` is a regular expression following the format accepted by libfa.
- `input_file` is a [Re-Pair](https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz)-compressed file (`.rp`).

**Example:**

```bash
# Compress a file
benchmark/repair110811/repair myfile.txt    # produces myfile.txt.rp

# Count matching lines
./zearch -c "hello.*world" myfile.txt.rp

# Print matching lines
./zearch -l "error|warning" logfile.txt.rp

# Boolean existence check
./zearch -b "^admin" users.txt.rp
```

## Comparison with Other Tools

We have compared the performance of **zearch** with the state-of-the-art approach for regular expression matching on compressed text. The comparison measures only the running time to count matching lines. The state-of-the-art baseline is:

```
{lz4,zstd} -dc compressed_file | {grep,rg,hyperscan} -c regex
```

The experiments show that **zearch** outperforms this baseline even when decompression and search are done in parallel. Pre-computed results are available [here](https://pevalme.github.io/zearch/graphs/index.html).

To reproduce the experiments, follow the steps below.

### Step 1 — Install All Tools

Run the install script from the `benchmark/` directory (see [Quick Start](#quick-start-install-all-tools) above).

### Step 2 — Prepare Benchmark Files

The `benchmark/generate_files.sh` script downloads real-world datasets (NASA web logs, OpenSubtitles, Project Gutenberg books, Google N-grams, CSV data) and produces compressed test files (`.rp`, `.zst`, `.lz4`, `.gz`, `.Z`) at sizes from 1 KB to 500 MB.

**Requirements:** approximately 12 GB of free disk space.

```bash
cd benchmark
bash generate_files.sh
```

The script will ask for confirmation before downloading. Pass `--quick` to skip files larger than 100 KB (useful for testing):

```bash
bash generate_files.sh --quick
```

The script creates sub-directories `benchmark/logs/`, `benchmark/subs/`, `benchmark/gutenberg/`, and optionally `benchmark/json/`, `benchmark/csv/`, `benchmark/yes/`, each containing the original text files and all compressed variants.

### Step 3 — Run the Benchmarks and Generate Graphs

The `graphs/generate_graphs.sh` script runs all benchmarks across datasets and sizes, writes timing results to JSON files in `graphs/`, and produces an `index.html` with embedded D3.js charts.

```bash
cd graphs
bash generate_graphs.sh                       # all file types, all sizes
bash generate_graphs.sh --small               # sizes up to 1MB only
bash generate_graphs.sh --types logs,subs     # specific file types only
bash generate_graphs.sh --small --types csv   # combine flags
```

Available `--types` values: `subs`, `gutenberg`, `csv`, `logs`, `qwerty`, `all` (default).

Alternatively, `graphs/generate_table.sh` runs a smaller fixed benchmark (files up to 100 KB) that also records compression ratios and decompression speeds:

```bash
cd graphs
bash generate_table.sh
```

Both scripts expect:
- `../zearch` binary at the project root
- `../benchmark/repair110811/repair` and `despair` binaries
- `../benchmark/{logs,subs,gutenberg,...}/original*.txt` files generated by `generate_files.sh`
- `graphs/hyperscan` binary (built by `install_tools.sh`)

Once complete, open `graphs/index.html` in a browser to view the results.
