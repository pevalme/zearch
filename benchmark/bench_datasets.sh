#!/bin/bash
# Benchmark: C zearch vs Rust zearch-rs using the same dataset types and regex
# patterns as graphs/generate_table.sh (logs, gutenberg, subtitles), up to 1MB.
#
# Patterns (identical to regsearch[] in generate_table.sh):
#   r1: what
#   r2: HTTP
#   r3: .
#   r4: I .* you
#   r5: [a-z]{4}
#   r6: [0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}
#   r7: [a-z]*[a-z]{3}
#   r8: [0-9]{4}

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

REPS=5

cleanup() { rm -rf "$TMPDIR_BM"; }
trap cleanup EXIT

# ── Generate synthetic corpora matching real dataset types ──────────────────

info "Generating synthetic corpora in $TMPDIR_BM ..."

python3 - "$TMPDIR_BM" <<'PYEOF'
import random, sys, os
rng = random.Random(42)
tmpdir = sys.argv[1]

months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
jul_aug_months = ['Jun','Jul','Aug']
methods = ['GET','POST','HEAD','PUT']
paths = ['/index.html','/images/logo.gif','/cgi-bin/query.pl','/pub/what/data.txt',
         '/search?q=what','/','/login','/logout','/about','/contact',
         '/pub/NASA/images/1995.jpg','/shuttle/countdown/']
statuses = [200,200,200,200,304,404,403,500]
agents = ['Mozilla/2.0','Mozilla/3.0','MSIE 2.0','Lynx/2.4']
hosts = ['piweba3y.prodigy.com','163.206.89.4','128.159.122.116',
         'kgtyk4.kget.edu','129.94.144.152','ts8-1.westwood.ts.ucla.edu',
         'uplherc.upl.com','163.206.137.21']

def log_line():
    host = rng.choice(hosts)
    day = rng.randint(1,31)
    mon = rng.choice(months)
    yr = rng.choice([1994,1995])
    h, m, s = rng.randint(0,23), rng.randint(0,59), rng.randint(0,59)
    meth = rng.choice(methods)
    path = rng.choice(paths)
    proto = 'HTTP/1.0'
    status = rng.choice(statuses)
    sz = rng.randint(100,50000)
    # occasionally embed a date in Jul/Aug/1995 to match r6
    if rng.random() < 0.05:
        mon = rng.choice(jul_aug_months)
        yr = 1995
        day = rng.randint(1,28)
    return f'{host} - - [{day:02d}/{mon}/{yr}:{h:02d}:{m:02d}:{s:02d} -0400] "{meth} {path} {proto}" {status} {sz}'

# Gutenberg-style prose
nouns = ['man','time','year','people','child','hand','life','day','world','school',
         'state','family','place','case','week','company','system','book','word','what']
verbs = ['know','think','take','come','give','look','make','tell','find','feel',
         'have','say','want','give','love','hate','need','see','use','get']
adj   = ['good','high','long','great','little','own','old','right','big','next',
         'last','young','important','public','private','real','best','free']
preps = ['with','from','into','about','over','after','through','during','before','between']

def prose_sentence():
    n = rng.randint(6,20)
    words = []
    for _ in range(n):
        r = rng.random()
        if r < 0.4:
            words.append(rng.choice(nouns))
        elif r < 0.7:
            words.append(rng.choice(verbs))
        elif r < 0.85:
            words.append(rng.choice(adj))
        else:
            words.append(rng.choice(preps))
    # occasionally embed "I ... you" pattern for r4
    if rng.random() < 0.04:
        words[0] = 'I'
        words[-1] = 'you'
    s = ' '.join(words)
    return s[0].upper() + s[1:] + '.'

def prose_line():
    k = rng.randint(1,4)
    return ' '.join(prose_sentence() for _ in range(k))

# Subtitle-style lines
sub_words = ['what','you','are','the','is','that','have','for','not','with',
             'this','they','from','but','what','can','your','all','will','there',
             'said','time','look','good','know','just','want','come','been','when',
             'her','him','she','who','back','did','get','him','had','our',
             'out','up','us','do','how','so','if','I','love','hate','need']

def sub_line():
    n = rng.randint(3,12)
    words = [rng.choice(sub_words) for _ in range(n)]
    # occasionally embed "I ... you"
    if rng.random() < 0.05:
        words[0] = 'I'
        words[-1] = 'you'
    return ' '.join(words)

datasets = {
    'logs': log_line,
    'gutenberg': prose_line,
    'subtitles': sub_line,
}

for name, gen in datasets.items():
    for size_label, target_bytes in [('100KB', 100*1024), ('1MB', 1024*1024), ('500MB', 500*1024*1024)]:
        lines = []
        total = 0
        while total < target_bytes:
            line = gen()
            lines.append(line)
            total += len(line) + 1
        text = '\n'.join(lines) + '\n'
        path = os.path.join(tmpdir, f'{name}_{size_label}.txt')
        with open(path, 'w') as f:
            f.write(text)
        print(f'  {path}: {len(text):,} bytes, {len(lines):,} lines', flush=True)
PYEOF

info "Compressing with Re-Pair ..."
for f in "$TMPDIR_BM"/*.txt; do
    "$REPAIR" "$f" 2>/dev/null
    info "  $(basename "$f").rp done"
done

# ── Regex patterns from generate_table.sh ─────────────────────────────────────
# regsearch[] array (zearch -c compatible)
PATTERNS=(
    "what"
    "HTTP"
    "."
    "I .* you"
    " [a-z]{4} "
    "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}"
    " [a-z]*[a-z]{3} "
    "[0-9]{4}"
)
PNAMES=("r1:what" "r2:HTTP" "r3:." "r4:I.*you" "r5:[a-z]{4}" "r6:date" "r7:[a-z]{3}+" "r8:[0-9]{4}")

# ── Timing helper ──────────────────────────────────────────────────────────────

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

for dataset in logs gutenberg subtitles; do
    printf "\n"
    head_ "============================================================"
    head_ " Dataset: $dataset  |  C zearch vs Rust zearch-rs  |  -c mode"
    head_ " Reps: $REPS  |  Patterns: r1-r8 (same as generate_table.sh)"
    head_ "============================================================"
    printf "\n"
    printf "%-8s  %-12s  %-22s  %10s  %10s  %10s\n" "SIZE" "PATTERN" "REGEX" "C (s)" "Rust (s)" "Speedup"
    printf "%-8s  %-12s  %-22s  %10s  %10s  %10s\n" "--------" "------------" "----------------------" "----------" "----------" "----------"

    for size in 100KB 1MB 500MB; do
        rp="$TMPDIR_BM/${dataset}_${size}.txt.rp"
        for idx in "${!PATTERNS[@]}"; do
            pat="${PATTERNS[$idx]}"
            pname="${PNAMES[$idx]}"
            c_t=$(time_secs "$ZEARCH_C" -c "$pat" "$rp")
            rs_t=$(time_secs "$ZEARCH_RS" -c "$pat" "$rp")
            speedup=$(printf "%.2f" "$(echo "scale=4; $c_t / $rs_t" | bc -l 2>/dev/null || echo 1)")
            printf "%-8s  %-12s  %-22s  %10s  %10s  %9sx\n" \
                "$size" "$pname" "$pat" "$c_t" "$rs_t" "$speedup"
        done
        echo ""
    done
done

ok "Benchmark complete."
