/*
 * zearch-rs: Rust reimplementation of zearch
 * Regular Expression Matching on Grammar-Compressed Text
 * (Ganty & Valero, DCC 2019)
 *
 * License: GPL v3 (same as original C implementation)
 */

#![allow(clippy::needless_range_loop)]

mod fa_sys;

use fa_sys::*;
use std::io::{self, Read, Write};

// ── Constants (matching C implementation) ────────────────────────────────────

const ALPHABET_SIZE: usize = 256;
const MAX_REGEX_SIZE: usize = 1024;
const SMALL_REGEX_BOUND: usize = 256;
const NUM_PAIRS_INITIAL: usize = 4;
const NUM_PAIRS_PER_STRUCT: usize = 2;
const COUNTER_TOP: u32 = 33_554_432; // 2^25
const MAX_PREALLOCATED: usize = 32768;
const CHAR_SIZE: usize = 256;
const MATCH_MAX_LENGTH: usize = 1000;

// ── Core data structures ─────────────────────────────────────────────────────

/// Linked-list node in the overflow allocator (matches C PAIR)
#[derive(Clone, Copy, Default)]
struct Pair {
    next_block: i16,
    next_index: i16,
    initial: [u8; NUM_PAIRS_PER_STRUCT],
    final_: [u8; NUM_PAIRS_PER_STRUCT],
}

/// Per-grammar-variable NFA transition info (matches C TRANSITION_FULL)
#[derive(Clone, Copy, Default)]
struct TransitionFull {
    /// Inline storage: states 0-255 only (u8)
    initial: [u8; NUM_PAIRS_INITIAL],
    final_: [u8; NUM_PAIRS_INITIAL],
    /// Overflow linked-list head (-1 if none)
    first_block: i16,
    first_index: i16,
    /// Matching line count (25-bit in C; we use u32 and check overflow externally)
    count: u32,
    new_lines: bool,
    is_there: bool,
    match_: bool,
    right: bool,
    left: bool,
    /// Next inline slot (wraps 0-3). 0 means "all 4 used" when is_there=true.
    pairs_used: u8,
}

/// Compact per-sequence-element info (matches C TRANSITION_SEQ)
#[derive(Clone, Copy, Default)]
struct TransitionSeq {
    new_lines: bool,
    match_: bool,
    right: bool,
    left: bool,
}

/// Grammar rule: variable → left_symbol right_symbol
#[derive(Clone, Copy, Default)]
struct GrammarRule {
    left_symbol: u32,
    right_symbol: u32,
}

// ── Memory allocator (matches C MEMORY) ──────────────────────────────────────

struct Memory {
    blocks: Vec<Vec<Pair>>,
    num_pos: usize,
}

impl Memory {
    fn new() -> Self {
        Memory {
            blocks: Vec::new(),
            num_pos: MAX_PREALLOCATED, // triggers allocation on first use
        }
    }

    fn malloc(&mut self) -> (i16, i16) {
        if self.num_pos == MAX_PREALLOCATED {
            self.blocks.push(vec![Pair::default(); MAX_PREALLOCATED]);
            self.num_pos = 0;
        }
        let block = (self.blocks.len() - 1) as i16;
        let pos = self.num_pos as i16;
        self.num_pos += 1;
        (block, pos)
    }

    #[inline(always)]
    fn get(&self, block: i16, index: i16) -> &Pair {
        &self.blocks[block as usize][index as usize]
    }

    #[inline(always)]
    fn get_mut(&mut self, block: i16, index: i16) -> &mut Pair {
        &mut self.blocks[block as usize][index as usize]
    }
}

// ── Bit reader (matches C BITIN) ─────────────────────────────────────────────

struct BitIn {
    data: Vec<u32>,
    pos: usize,   // current word index
    bitbuf: u32,
    bitlen: u32,
}

impl BitIn {
    fn from_bytes(bytes: &[u8]) -> Self {
        // Convert bytes to u32 words using native (little-endian) byte order,
        // matching C's fread(buf, sizeof(unsigned int), ...) on x86.
        // readBits then processes each word from MSB to LSB.
        let mut data = Vec::with_capacity((bytes.len() + 3) / 4);
        let mut i = 0;
        while i + 4 <= bytes.len() {
            data.push(u32::from_le_bytes([bytes[i], bytes[i+1], bytes[i+2], bytes[i+3]]));
            i += 4;
        }
        if i < bytes.len() {
            let mut buf = [0u8; 4];
            buf[..bytes.len()-i].copy_from_slice(&bytes[i..]);
            data.push(u32::from_le_bytes(buf));
        }
        BitIn { data, pos: 0, bitbuf: 0, bitlen: 0 }
    }

    #[inline(always)]
    fn read_bits(&mut self, rblen: u32) -> u32 {
        const W_BITS: u32 = 32;
        if rblen < self.bitlen {
            let x = self.bitbuf >> (W_BITS - rblen);
            self.bitbuf = self.bitbuf.wrapping_shl(rblen);
            self.bitlen -= rblen;
            x
        } else {
            let s = rblen - self.bitlen;
            // Combine remaining bits + s bits from next word
            let x = if self.bitlen + s == 0 {
                0
            } else if s == 0 {
                self.bitbuf >> (W_BITS - self.bitlen)
            } else {
                self.bitbuf >> (W_BITS - self.bitlen - s)
            };
            let word = if self.pos < self.data.len() { self.data[self.pos] } else { 0 };
            self.pos += 1;
            self.bitbuf = word;
            self.bitlen = W_BITS - s;
            if s != 0 {
                let result = x | (self.bitbuf >> self.bitlen);
                self.bitbuf = self.bitbuf.wrapping_shl(s);
                result
            } else {
                x
            }
        }
    }
}

// ── Stack ─────────────────────────────────────────────────────────────────────

struct Stack {
    data: Vec<u32>,
}

impl Stack {
    fn new() -> Self {
        Stack { data: Vec::with_capacity(1024) }
    }
    #[inline(always)]
    fn push(&mut self, v: u32) { self.data.push(v); }
    #[inline(always)]
    fn pop(&mut self) -> u32 { self.data.pop().expect("EMPTY STACK") }
}

// ── Main state struct ─────────────────────────────────────────────────────────

struct ZearchState {
    automaton: Vec<TransitionFull>,
    automaton_seq: Vec<TransitionSeq>,
    grammar: Vec<GrammarRule>,

    recently_added: Vec<i32>, // [MAX_REGEX_SIZE * MAX_REGEX_SIZE], flat
    reached_states: [Vec<i32>; 2],
    rs_idx: usize,  // which of the two reached_states arrays is "rs"

    list_dots: Vec<u16>,
    dots: Vec<u8>,
    final_states: Vec<u8>,
    num_edges: Vec<u16>,
    edges: Vec<Vec<u16>>, // edges[q] = list of states reachable from q

    num_states: usize,
    num_dots: usize,

    mem: Memory,
    num_rules: u32,
    counting_overflows: u32,
    seq_counter: i32,
    seq_counter_new: i32,

    // Current rule context (set before calling add_rule etc.)
    rule: u32,
    left: u32,
    right: u32,

    // Temporaries for current rule
    tleft: TransitionFull,
    tright: TransitionFull,
    trule: TransitionFull,
    tsleft: TransitionSeq,
    tsrule: TransitionSeq,

    mode: u8, // b'c', b'l', b'a', b'b'
    expand: bool,

    // Output buffer for match printing
    buffer: Vec<u8>,
    bufpos: usize,
}

impl ZearchState {
    fn new(num_rules: u32, seq_len: usize, mode: u8) -> Self {
        let mut s = ZearchState {
            automaton: vec![TransitionFull { first_block: -1, first_index: -1, ..Default::default() }; num_rules as usize],
            automaton_seq: if mode != b'c' && mode != b'b' {
                vec![TransitionSeq::default(); seq_len]
            } else {
                Vec::new()
            },
            grammar: if mode != b'c' && mode != b'b' {
                vec![GrammarRule::default(); num_rules as usize + seq_len]
            } else {
                Vec::new()
            },
            recently_added: vec![0i32; MAX_REGEX_SIZE * MAX_REGEX_SIZE],
            reached_states: [
                vec![-1i32; MAX_REGEX_SIZE],
                vec![-1i32; MAX_REGEX_SIZE],
            ],
            rs_idx: 0,
            list_dots: vec![0u16; MAX_REGEX_SIZE],
            dots: vec![0u8; MAX_REGEX_SIZE],
            final_states: vec![0u8; MAX_REGEX_SIZE],
            num_edges: vec![0u16; MAX_REGEX_SIZE],
            edges: vec![vec![0u16; MAX_REGEX_SIZE]; MAX_REGEX_SIZE],
            num_states: 0,
            num_dots: 0,
            mem: Memory::new(),
            num_rules,
            counting_overflows: 0,
            seq_counter: 0,
            seq_counter_new: 0,
            rule: 0,
            left: 0,
            right: 0,
            tleft: TransitionFull { first_block: -1, first_index: -1, ..Default::default() },
            tright: TransitionFull { first_block: -1, first_index: -1, ..Default::default() },
            trule: TransitionFull { first_block: -1, first_index: -1, ..Default::default() },
            tsleft: TransitionSeq::default(),
            tsrule: TransitionSeq::default(),
            mode,
            expand: false,
            buffer: vec![0u8; MATCH_MAX_LENGTH],
            bufpos: 0,
        };
        // Newlines generate new_lines
        s.automaton[10].new_lines = true;
        s.automaton[13].new_lines = true;
        // Initial state is always a "dot" state
        s.dots[0] = 1;
        s
    }

    fn recently_added_get(&self, i: usize, f: usize) -> i32 {
        self.recently_added[i * MAX_REGEX_SIZE + f]
    }

    fn recently_added_set(&mut self, i: usize, f: usize, val: i32) {
        self.recently_added[i * MAX_REGEX_SIZE + f] = val;
    }

    // ── NFA initialization (via libfa FFI) ────────────────────────────────

    fn initialize_automaton(&mut self, minimize: bool, regex: &str) {
        unsafe {
            let regex_cstr = std::ffi::CString::new(regex).unwrap();
            let mut fa_result: *mut Fa = std::ptr::null_mut();
            let ret = fa_compile(regex_cstr.as_ptr(), regex.len(), &mut fa_result);
            if ret != 0 {
                eprintln!("Error compiling regex: {}", ret);
                std::process::exit(-1);
            }
            if minimize {
                fa_minimize(fa_result);
            }

            let mut st = fa_state_initial(fa_result);
            if st.is_null() {
                eprintln!("Error: null initial state");
                std::process::exit(-1);
            }

            // Collect all states and assign indices
            let mut hashes: Vec<*mut State> = Vec::new();
            let mut cur = st;
            while !cur.is_null() {
                let idx = hashes.len();
                hashes.push(cur);
                if fa_state_is_accepting(cur) {
                    self.dots[idx] = 1;
                    self.final_states[idx] = 1;
                }
                cur = fa_state_next(cur);
            }
            self.num_states = hashes.len();

            // Build transitions
            st = fa_state_initial(fa_result);
            let mut from: usize = 0;
            while !st.is_null() {
                let num_trans = fa_state_num_trans(st);
                let mut i = 0usize;
                while i < num_trans {
                    let mut st2: *mut State = std::ptr::null_mut();
                    let mut begin: u8 = 0;
                    let mut end: u8 = 0;
                    if fa_state_trans(st, i, &mut st2, &mut begin, &mut end) == -1 {
                        eprintln!("Error reading transition");
                    }
                    // Detect wildcard (dot): two transitions covering [0-9] and [11-255] self-loops
                    if st2 == st && begin == 0 && end == 9 {
                        let mut st3: *mut State = std::ptr::null_mut();
                        let mut begin2: u8 = 0;
                        let mut end2: u8 = 0;
                        if i + 1 < num_trans {
                            fa_state_trans(st, i + 1, &mut st3, &mut begin2, &mut end2);
                        }
                        if st3 == st && begin2 == 11 && end2 == 255 {
                            // It's a dot (wildcard) self-loop
                            self.dots[from] = 1;
                            self.list_dots[self.num_dots] = from as u16;
                            self.num_dots += 1;
                            i += 2;
                            continue;
                        } else {
                            // Not a wildcard, add individual edges
                            for r in 0u8..=9u8 {
                                self.rule = r as u32;
                                self.add_edge_direct(from as u8, from as u8);
                            }
                            for r in begin2..=end2 {
                                self.rule = r as u32;
                                self.add_edge_direct(from as u8, from as u8);
                            }
                        }
                    } else {
                        // Find destination state index
                        let to = hashes.iter().position(|&h| h == st2).unwrap_or(0);
                        for r in begin..=end {
                            self.rule = r as u32;
                            self.add_edge_direct(from as u8, to as u8);
                            if from == 0 && self.final_states[to] != 0 {
                                self.automaton[r as usize].match_ = true;
                            }
                        }
                    }
                    i += 1;
                }
                st = fa_state_next(st);
                from += 1;
            }

            fa_free(fa_result);
        }
    }

    // ── Edge addition ─────────────────────────────────────────────────────

    /// Add edge to trule (lazy - doesn't write to automaton[rule] yet)
    #[inline(always)]
    fn add_edge(&mut self, i: u8, f: u8) {
        let rule = self.rule as i32;
        self.recently_added_set(i as usize, f as usize, rule);

        let trule = &mut self.trule;
        if !trule.is_there {
            // First edge
            trule.is_there = true;
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                trule.pairs_used = 0;
                trule.first_block = -1; // will be set below
                trule.first_index = -1;
                drop(trule);
                let (block, index) = self.mem.malloc();
                self.trule.first_block = block;
                self.trule.first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
            } else {
                trule.first_block = -1;
                trule.first_index = -1;
                let pu = trule.pairs_used as usize;
                trule.initial[pu] = i;
                trule.final_[pu] = f;
                trule.pairs_used += 1;
            }
        } else if self.trule.pairs_used == 0 {
            // Inline full or memory mode
            if self.trule.first_block == -1 {
                // Allocate first memory block
                let (block, index) = self.mem.malloc();
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
                self.trule.first_block = block;
                self.trule.first_index = index;
            } else {
                // Find last block and append
                let mut blk = self.trule.first_block;
                let mut idx = self.trule.first_index;
                loop {
                    let nb = self.mem.get(blk, idx).next_block;
                    let ni = self.mem.get(blk, idx).next_index;
                    if nb == -1 { break; }
                    blk = nb; idx = ni;
                }
                let p = self.mem.get_mut(blk, idx);
                if p.initial[1] == 0 && p.final_[1] == 0 {
                    p.initial[1] = i;
                    p.final_[1] = f;
                } else {
                    let (nb, ni) = self.mem.malloc();
                    self.mem.get_mut(blk, idx).next_block = nb;
                    self.mem.get_mut(blk, idx).next_index = ni;
                    let p2 = self.mem.get_mut(nb, ni);
                    p2.initial[0] = i;
                    p2.final_[0] = f;
                    p2.next_block = -1;
                    p2.next_index = -1;
                }
            }
        } else {
            // Inline has space
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                // Switch to memory mode (inline pairs remain)
                self.trule.pairs_used = 0;
                let (block, index) = self.mem.malloc();
                self.trule.first_block = block;
                self.trule.first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
            } else {
                let pu = self.trule.pairs_used as usize;
                self.trule.initial[pu] = i;
                self.trule.final_[pu] = f;
                if pu == NUM_PAIRS_INITIAL - 1 {
                    self.trule.pairs_used = 0;
                } else {
                    self.trule.pairs_used += 1;
                }
            }
        }
    }

    /// Add edge directly to automaton[rule] (used during NFA init)
    #[inline(always)]
    fn add_edge_direct(&mut self, i: u8, f: u8) {
        let rule = self.rule as usize;
        if rule == 10 || rule == 13 { return; }

        if !self.automaton[rule].is_there {
            self.automaton[rule].is_there = true;
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                self.automaton[rule].pairs_used = 0;
                let (block, index) = self.mem.malloc();
                self.automaton[rule].first_block = block;
                self.automaton[rule].first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
            } else {
                self.automaton[rule].first_block = -1;
                self.automaton[rule].first_index = -1;
                let pu = self.automaton[rule].pairs_used as usize;
                self.automaton[rule].initial[pu] = i;
                self.automaton[rule].final_[pu] = f;
                self.automaton[rule].pairs_used += 1;
            }
        } else if self.automaton[rule].pairs_used == 0 {
            if self.automaton[rule].first_block == -1 {
                let (block, index) = self.mem.malloc();
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
                self.automaton[rule].first_block = block;
                self.automaton[rule].first_index = index;
            } else {
                let mut blk = self.automaton[rule].first_block;
                let mut idx = self.automaton[rule].first_index;
                loop {
                    let nb = self.mem.get(blk, idx).next_block;
                    let ni = self.mem.get(blk, idx).next_index;
                    if nb == -1 { break; }
                    blk = nb; idx = ni;
                }
                let p = self.mem.get_mut(blk, idx);
                if p.initial[1] == 0 && p.final_[1] == 0 {
                    p.initial[1] = i;
                    p.final_[1] = f;
                } else {
                    let (nb, ni) = self.mem.malloc();
                    self.mem.get_mut(blk, idx).next_block = nb;
                    self.mem.get_mut(blk, idx).next_index = ni;
                    {
                        let p2 = self.mem.get_mut(nb, ni);
                        p2.initial[0] = i;
                        p2.final_[0] = f;
                        p2.next_block = -1;
                        p2.next_index = -1;
                    }
                    self.recently_added_set(i as usize, f as usize, rule as i32);
                }
            }
        } else {
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                // Switch to memory (existing inline pairs remain)
                for it in self.automaton[rule].pairs_used as usize..NUM_PAIRS_INITIAL {
                    self.automaton[rule].initial[it] = 0;
                    self.automaton[rule].final_[it] = 0;
                }
                self.automaton[rule].pairs_used = 0;
                let (block, index) = self.mem.malloc();
                self.automaton[rule].first_block = block;
                self.automaton[rule].first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i;
                p.final_[0] = f;
                p.next_block = -1;
                p.next_index = -1;
            } else {
                let pu = self.automaton[rule].pairs_used as usize;
                self.automaton[rule].initial[pu] = i;
                self.automaton[rule].final_[pu] = f;
                if pu == NUM_PAIRS_INITIAL - 1 {
                    self.automaton[rule].pairs_used = 0;
                } else {
                    self.automaton[rule].pairs_used += 1;
                }
            }
        }
    }

    // ── Counting functions ─────────────────────────────────────────────────

    #[inline(always)]
    fn prop_count(&mut self) {
        let tleft = self.tleft;
        let tright = self.tright;
        self.trule.match_ = true;
        self.trule.count = tleft.count.wrapping_add(tright.count);
        if tleft.new_lines {
            self.trule.left = tleft.left;
            if tright.new_lines {
                self.trule.right = tright.right;
                let cross = tright.left || tleft.right;
                if cross { self.trule.count = self.trule.count.wrapping_add(1); }
                self.expand = cross;
            } else {
                self.trule.right = tleft.right || tright.match_;
            }
        } else if tright.new_lines {
            self.trule.left = tright.left || tleft.match_;
            self.trule.right = tright.right;
        }
    }

    #[inline(always)]
    fn incr_count(&mut self) {
        let tleft = self.tleft;
        let tright = self.tright;
        self.trule.match_ = true;
        self.trule.count = tleft.count.wrapping_add(tright.count);
        if tleft.new_lines {
            self.trule.left = tleft.left;
            if tright.new_lines {
                self.trule.right = tright.right;
                self.trule.count = self.trule.count.wrapping_add(1);
                self.expand = true;
            } else {
                self.trule.right = true;
            }
        } else if tright.new_lines {
            self.trule.left = true;
            self.trule.right = tright.right;
        }
    }

    #[inline(always)]
    fn incr_count_l1(symbol: usize, automaton: &mut [TransitionFull]) {
        automaton[symbol].match_ = true;
    }

    #[inline(always)]
    fn prop_count_seq(&mut self) {
        let tsleft = self.tsleft;
        let tright = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter_new = self.seq_counter + tright.count as i32;
        if tsleft.new_lines {
            self.tsrule.left = tsleft.left;
            if tright.new_lines {
                self.tsrule.right = tright.right;
                let cross = tright.left || tsleft.right;
                if cross { self.seq_counter_new += 1; }
                self.expand = cross;
            } else {
                self.tsrule.right = tsleft.right || tright.match_;
            }
        } else if tright.new_lines {
            self.tsrule.left = tright.left || tsleft.match_;
            self.tsrule.right = tright.right;
        }
    }

    #[inline(always)]
    fn incr_count_seq(&mut self) {
        let tsleft = self.tsleft;
        let tright = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter_new = self.seq_counter + tright.count as i32;
        if tsleft.new_lines {
            self.tsrule.left = tsleft.left;
            if tright.new_lines {
                self.tsrule.right = tright.right;
                self.seq_counter_new += 1;
                self.expand = true;
            } else {
                self.tsrule.right = true;
            }
        } else if tright.new_lines {
            self.tsrule.left = true;
            self.tsrule.right = tright.right;
        }
    }

    #[inline(always)]
    fn incr_count_seq_1(&mut self, middle_state: bool) {
        let tleft = self.tleft;
        let tright = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter = tleft.count as i32 + tright.count as i32;
        if tleft.new_lines {
            self.tsrule.left = tleft.left;
            if tright.new_lines {
                self.tsrule.right = tright.right;
                let add = tright.left || tleft.right || middle_state;
                if add { self.seq_counter += 1; }
                self.expand = add;
            } else {
                self.tsrule.right = tleft.right || tright.match_ || middle_state;
            }
        } else if tright.new_lines {
            self.tsrule.left = tright.left || tleft.match_ || middle_state;
            self.tsrule.right = tright.right;
        }
    }

    // ── Saturation construction: add_rule ────────────────────────────────

    fn add_rule(&mut self) {
        let left = self.left as usize;
        let right = self.right as usize;
        let rule = self.rule as i32;

        self.tleft = self.automaton[left];
        self.tright = self.automaton[right];
        self.trule = TransitionFull { first_block: -1, first_index: -1, ..Default::default() };
        self.expand = false;

        let tleft = self.tleft;
        let tright = self.tright;

        self.trule.new_lines = tleft.new_lines || tright.new_lines;
        self.trule.match_ = false;
        self.trule.left = false;
        self.trule.right = false;

        if tright.match_ || tleft.match_ {
            self.prop_count();
        }

        if !tleft.is_there && !tright.is_there {
            return;
        }

        // Case 1: No left transitions, or left has no newlines and right starts from 0
        if !tleft.is_there || (tright.left && !tleft.new_lines && tright.is_there) {
            if tright.right { return; }

            // Only propagate right transitions (which start from state 0)
            if tleft.new_lines {
                // left has newlines: only add right edges that start at 0 and go to non-final
                self.for_each_edge_right(|s, initial, final_| {
                    if initial == 0 && s.final_states[final_ as usize] == 0 {
                        if s.recently_added_get(0, final_ as usize) != rule {
                            s.add_edge(0, final_);
                        }
                    }
                });
            } else {
                // left has no newlines: propagate dot transitions from right
                self.for_each_edge_right(|s, initial, final_| {
                    if s.dots[initial as usize] != 0
                        && (initial != 0 || s.final_states[final_ as usize] == 0)
                    {
                        if s.recently_added_get(initial as usize, final_ as usize) != rule {
                            s.add_edge(initial, final_);
                        }
                    }
                });
            }
            return;
        }

        // Case 2: Both sides have transitions (or right is complex)
        let tright_is_there = tright.is_there;
        let tright_right = tright.right;
        let tright_new_lines = tright.new_lines;
        let tleft_right = tleft.right;
        let tleft_new_lines = tleft.new_lines;

        if tright_is_there && (!tleft_right || tright_new_lines != false) {
            // Build right-side edge lookup table
            self.num_edges.iter_mut().take(self.num_states).for_each(|x| *x = 0);

            let tright_copy = self.tright;

            if tleft_new_lines {
                // For tleft with newlines: right edges from state 0 are auto-added
                self.for_each_edge_right_lookup(tright_copy, |s, initial, final_| {
                    s.edges[initial as usize][s.num_edges[initial as usize] as usize] = final_ as u16;
                    s.num_edges[initial as usize] += 1;
                    if initial == 0 && s.final_states[final_ as usize] == 0 {
                        if s.recently_added_get(0, final_ as usize) != rule {
                            s.add_edge(0, final_);
                        }
                    }
                });
            } else {
                // Standard: right edges from dot states are auto-added
                self.for_each_edge_right_lookup(tright_copy, |s, initial, final_| {
                    s.edges[initial as usize][s.num_edges[initial as usize] as usize] = final_ as u16;
                    s.num_edges[initial as usize] += 1;
                    if s.dots[initial as usize] != 0
                        && (initial != 0 || s.final_states[final_ as usize] == 0)
                    {
                        if s.recently_added_get(initial as usize, final_ as usize) != rule {
                            s.add_edge(initial, final_);
                        }
                    }
                });
            }

            // Compose: for each left edge (q1 → qm), look up right edges from qm
            let mut mid = false;
            let tleft_copy = self.tleft;
            self.for_each_edge_left_compose(tleft_copy, tright_new_lines, rule, &mut mid);

            if mid { self.incr_count(); }
            return;
        }

        // Case 3: No right transitions (or left.right=true and right has no newlines)
        if tleft.left { return; }

        if tright_new_lines {
            self.for_each_edge_left(|s, initial, final_| {
                if s.final_states[final_ as usize] != 0 && initial != 0 {
                    if s.recently_added_get(initial as usize, final_ as usize) != rule {
                        s.add_edge(initial, final_);
                    }
                }
            });
        } else {
            self.for_each_edge_left(|s, initial, final_| {
                if s.dots[final_ as usize] != 0
                    && (initial != 0 || s.final_states[final_ as usize] == 0)
                {
                    if s.recently_added_get(initial as usize, final_ as usize) != rule {
                        s.add_edge(initial, final_);
                    }
                }
            });
        }
    }

    // Helper: iterate right edges and call closure
    fn for_each_edge_right<F>(&mut self, mut f: F)
    where F: FnMut(&mut Self, u8, u8)
    {
        let tright = self.tright;
        let rpairs = if tright.pairs_used != 0 { tright.pairs_used as usize } else { NUM_PAIRS_INITIAL };
        for it in 0..rpairs {
            let (ini, fin) = (tright.initial[it], tright.final_[it]);
            f(self, ini, fin);
        }
        let mut blk = tright.first_block;
        let mut idx = tright.first_index;
        while blk != -1 {
            let pair = *self.mem.get(blk, idx);
            if pair.final_[0] == 0 { break; }
            for it in 0..NUM_PAIRS_PER_STRUCT {
                if pair.final_[it] == 0 { break; }
                let (ini, fin) = (pair.initial[it], pair.final_[it]);
                f(self, ini, fin);
            }
            blk = pair.next_block;
            idx = pair.next_index;
        }
    }

    fn for_each_edge_right_lookup<F>(&mut self, tright: TransitionFull, mut f: F)
    where F: FnMut(&mut Self, u8, u8)
    {
        let rpairs = if tright.pairs_used != 0 { tright.pairs_used as usize } else { NUM_PAIRS_INITIAL };
        for it in 0..rpairs {
            let (ini, fin) = (tright.initial[it], tright.final_[it]);
            f(self, ini, fin);
        }
        let mut blk = tright.first_block;
        let mut idx = tright.first_index;
        while blk != -1 {
            let pair = *self.mem.get(blk, idx);
            if pair.final_[0] == 0 { break; }
            for it in 0..NUM_PAIRS_PER_STRUCT {
                if pair.final_[it] == 0 { break; }
                let (ini, fin) = (pair.initial[it], pair.final_[it]);
                f(self, ini, fin);
            }
            blk = pair.next_block;
            idx = pair.next_index;
        }
    }

    fn for_each_edge_left<F>(&mut self, mut f: F)
    where F: FnMut(&mut Self, u8, u8)
    {
        let tleft = self.tleft;
        let lpairs = if tleft.pairs_used != 0 { tleft.pairs_used as usize } else { NUM_PAIRS_INITIAL };
        for it in 0..lpairs {
            let (ini, fin) = (tleft.initial[it], tleft.final_[it]);
            f(self, ini, fin);
        }
        let mut blk = tleft.first_block;
        let mut idx = tleft.first_index;
        while blk != -1 {
            let pair = *self.mem.get(blk, idx);
            if pair.final_[0] == 0 { break; }
            for it in 0..NUM_PAIRS_PER_STRUCT {
                if pair.final_[it] == 0 { break; }
                let (ini, fin) = (pair.initial[it], pair.final_[it]);
                f(self, ini, fin);
            }
            blk = pair.next_block;
            idx = pair.next_index;
        }
    }

    fn for_each_edge_left_compose(&mut self, tleft: TransitionFull, tright_new_lines: bool, rule: i32, mid: &mut bool) {
        let lpairs = if tleft.pairs_used != 0 { tleft.pairs_used as usize } else { NUM_PAIRS_INITIAL };
        for it in 0..lpairs {
            let (ini, fin) = (tleft.initial[it], tleft.final_[it]);
            self.compose_left_edge(ini, fin, tright_new_lines, rule, mid);
        }
        let mut blk = tleft.first_block;
        let mut idx = tleft.first_index;
        while blk != -1 {
            let pair = *self.mem.get(blk, idx);
            if pair.final_[0] == 0 { break; }
            for it in 0..NUM_PAIRS_PER_STRUCT {
                if pair.final_[it] == 0 { break; }
                let (ini, fin) = (pair.initial[it], pair.final_[it]);
                self.compose_left_edge(ini, fin, tright_new_lines, rule, mid);
            }
            blk = pair.next_block;
            idx = pair.next_index;
        }
    }

    #[inline(always)]
    fn compose_left_edge(&mut self, ini: u8, fin: u8, tright_new_lines: bool, rule: i32, mid: &mut bool) {
        // Add dot self-loop if applicable
        if self.dots[fin as usize] != 0 && (self.final_states[fin as usize] != 0 || !tright_new_lines) {
            if ini != 0 || self.final_states[fin as usize] == 0 {
                if self.recently_added_get(ini as usize, fin as usize) != rule {
                    self.add_edge(ini, fin);
                }
            }
        }
        // Compose with right-side edges
        let ne = self.num_edges[fin as usize] as usize;
        for k in 0..ne {
            let dest = self.edges[fin as usize][k] as u8;
            if ini == 0 && self.final_states[dest as usize] != 0 {
                *mid |= fin != 0 && self.final_states[fin as usize] == 0;
            } else {
                if self.recently_added_get(ini as usize, dest as usize) != rule {
                    self.add_edge(ini, dest);
                }
            }
        }
    }

    // ── Sequence rule processing ──────────────────────────────────────────

    fn add_rule_seq(&mut self) {
        let rule = self.rule;
        let left = self.left;
        let right = self.right;
        let num_rules = self.num_rules;
        let rs_cur = self.rs_idx;
        let rs_next = 1 - rs_cur;

        if rule > num_rules {
            // Normal case: extend sequence by one more element
            self.tsleft = self.automaton_seq[(left - num_rules) as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();
            self.seq_counter_new = 0;

            let tright = self.tright;
            let tright_new_lines = tright.new_lines;
            self.tsrule.new_lines = self.tsleft.new_lines || tright_new_lines;

            let mut mid = false;

            // Propagate reached states through right transitions
            if tright.is_there {
                let tright_copy = tright;
                let rpairs = if tright_copy.pairs_used != 0 { tright_copy.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..rpairs {
                    let (ini, fin) = (tright_copy.initial[it] as usize, tright_copy.final_[it] as usize);
                    if self.reached_states[rs_cur][ini] == left as i32 {
                        self.reached_states[rs_next][fin] = rule as i32;
                        mid |= self.final_states[fin] != 0 && ini != 0 && self.final_states[ini] == 0;
                    }
                }
                let mut blk = tright_copy.first_block;
                let mut idx = tright_copy.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if self.reached_states[rs_cur][ini] == left as i32 {
                            self.reached_states[rs_next][fin] = rule as i32;
                            mid |= self.final_states[fin] != 0 && ini != 0 && self.final_states[ini] == 0;
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            // Handle dot states
            if !tright_new_lines {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_cur][ds] == left as i32 {
                        self.reached_states[rs_next][ds] = rule as i32;
                    }
                }
            }

            // Swap rs
            self.rs_idx = rs_next;

            if mid {
                self.incr_count_seq();
            } else if self.tsleft.match_ || self.tright.match_ {
                self.prop_count_seq();
            }
            self.seq_counter = self.seq_counter_new;
            self.reached_states[self.rs_idx][0] = rule as i32;
        } else {
            // First element of sequence
            self.tleft = self.automaton[left as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();

            let tleft = self.tleft;
            let tright = self.tright;
            self.tsrule.new_lines = tleft.new_lines || tright.new_lines;

            let rs_a = 0usize;
            let rs_b = 1usize;

            let mut mid = false;
            let mut added = false;

            // Build reachability from left transitions
            if tleft.is_there {
                let lpairs = if tleft.pairs_used != 0 { tleft.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..lpairs {
                    let (ini, fin) = (tleft.initial[it] as usize, tleft.final_[it] as usize);
                    if ini == 0 || self.reached_states[rs_a][ini] == -1 {
                        self.reached_states[rs_a][fin] = left as i32;
                        if self.final_states[fin] != 0 {
                            added = true;
                            mid |= fin != 0 && self.final_states[fin] == 0;
                        }
                    }
                }
                let mut blk = tleft.first_block;
                let mut idx = tleft.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if ini == 0 || self.reached_states[rs_a][ini] == -1 {
                            self.reached_states[rs_a][fin] = left as i32;
                            if self.final_states[fin] != 0 {
                                added = true;
                                mid |= fin != 0 && self.final_states[fin] == 0;
                            }
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            // Propagate through right transitions
            if tright.is_there {
                let rpairs = if tright.pairs_used != 0 { tright.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..rpairs {
                    let (ini, fin) = (tright.initial[it] as usize, tright.final_[it] as usize);
                    if ini == 0 || self.reached_states[rs_a][ini] == left as i32 {
                        self.reached_states[rs_b][fin] = rule as i32;
                        if self.final_states[fin] != 0 {
                            added = true;
                            mid |= ini != 0 && self.final_states[ini] == 0;
                        }
                    }
                }
                let mut blk = tright.first_block;
                let mut idx = tright.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if ini == 0 || self.reached_states[rs_a][ini] == left as i32 {
                            self.reached_states[rs_b][fin] = rule as i32;
                            if self.final_states[fin] != 0 {
                                added = true;
                                mid |= ini != 0 && self.final_states[ini] == 0;
                            }
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            // Dot states
            if !tright.new_lines {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_a][ds] == left as i32 {
                        self.reached_states[rs_b][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_b;
            self.reached_states[self.rs_idx][0] = rule as i32;

            if mid {
                self.incr_count_seq_1(true);
            } else if tleft.match_ || tright.match_ || added {
                self.incr_count_seq_1(false);
            }
        }
    }

    fn add_rule_seq_count(&mut self) {
        let rule = self.rule;
        let left = self.left;
        let right = self.right;
        let num_rules = self.num_rules;
        let rs_cur = self.rs_idx;
        let rs_next = 1 - rs_cur;

        if rule > num_rules {
            // Normal case
            self.tsleft = self.tsrule;
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();
            self.seq_counter_new = 0;

            let tright = self.tright;
            let tright_new_lines = tright.new_lines;
            self.tsrule.new_lines = self.tsleft.new_lines || tright_new_lines;

            // Early exit optimization
            if tright.right && (self.tsleft.right || tright.left) {
                self.incr_count_seq();
                self.reached_states[rs_next][0] = rule as i32;
                self.seq_counter = self.seq_counter_new;
                self.rs_idx = rs_next;
                self.reached_states[self.rs_idx][0] = rule as i32;
                return;
            }

            let mut mid = false;

            if tright.is_there {
                let tright_copy = tright;
                let rpairs = if tright_copy.pairs_used != 0 { tright_copy.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..rpairs {
                    let (ini, fin) = (tright_copy.initial[it] as usize, tright_copy.final_[it] as usize);
                    if self.reached_states[rs_cur][ini] == left as i32 {
                        self.reached_states[rs_next][fin] = rule as i32;
                        mid |= self.final_states[fin] != 0 && ini != 0 && self.final_states[ini] == 0;
                    }
                }
                let mut blk = tright_copy.first_block;
                let mut idx = tright_copy.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if self.reached_states[rs_cur][ini] == left as i32 {
                            self.reached_states[rs_next][fin] = rule as i32;
                            mid |= self.final_states[fin] != 0 && ini != 0 && self.final_states[ini] == 0;
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            if !tright_new_lines {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_cur][ds] == left as i32 {
                        self.reached_states[rs_next][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_next;

            if mid {
                self.incr_count_seq();
            } else if self.tsleft.match_ || tright.match_ {
                self.prop_count_seq();
            }

            self.seq_counter = self.seq_counter_new;
            self.reached_states[self.rs_idx][0] = rule as i32;
        } else {
            // First element
            self.tleft = self.automaton[left as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();

            let tleft = self.tleft;
            let tright = self.tright;
            self.tsrule.new_lines = tleft.new_lines || tright.new_lines;

            let rs_a = 0usize;
            let rs_b = 1usize;
            let mut mid = false;
            let mut added = false;

            if tleft.is_there {
                let lpairs = if tleft.pairs_used != 0 { tleft.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..lpairs {
                    let (ini, fin) = (tleft.initial[it] as usize, tleft.final_[it] as usize);
                    if ini == 0 || self.reached_states[rs_a][ini] == -1 {
                        self.reached_states[rs_a][fin] = left as i32;
                        if self.final_states[fin] != 0 {
                            added = true;
                            mid |= fin != 0 && self.final_states[fin] == 0;
                        }
                    }
                }
                let mut blk = tleft.first_block;
                let mut idx = tleft.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if ini == 0 || self.reached_states[rs_a][ini] == -1 {
                            self.reached_states[rs_a][fin] = left as i32;
                            if self.final_states[fin] != 0 {
                                added = true;
                                mid |= fin != 0 && self.final_states[fin] == 0;
                            }
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            if tright.is_there {
                let rpairs = if tright.pairs_used != 0 { tright.pairs_used as usize } else { NUM_PAIRS_INITIAL };
                for it in 0..rpairs {
                    let (ini, fin) = (tright.initial[it] as usize, tright.final_[it] as usize);
                    if ini == 0 || self.reached_states[rs_a][ini] == left as i32 {
                        self.reached_states[rs_b][fin] = rule as i32;
                        if self.final_states[fin] != 0 {
                            added = true;
                            mid |= ini != 0 && self.final_states[ini] == 0;
                        }
                    }
                }
                let mut blk = tright.first_block;
                let mut idx = tright.first_index;
                while blk != -1 {
                    let pair = *self.mem.get(blk, idx);
                    if pair.final_[0] == 0 { break; }
                    for it in 0..NUM_PAIRS_PER_STRUCT {
                        if pair.final_[it] == 0 { break; }
                        let (ini, fin) = (pair.initial[it] as usize, pair.final_[it] as usize);
                        if ini == 0 || self.reached_states[rs_a][ini] == left as i32 {
                            self.reached_states[rs_b][fin] = rule as i32;
                            if self.final_states[fin] != 0 {
                                added = true;
                                mid |= ini != 0 && self.final_states[ini] == 0;
                            }
                        }
                    }
                    blk = pair.next_block;
                    idx = pair.next_index;
                }
            }

            if !tright.new_lines {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_a][ds] == left as i32 {
                        self.reached_states[rs_b][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_b;
            self.reached_states[self.rs_idx][0] = rule as i32;

            if mid {
                self.incr_count_seq_1(true);
            } else if tleft.match_ || tright.match_ || added {
                self.incr_count_seq_1(false);
            }
        }
    }

    // ── Match expansion (for -l and -a modes) ────────────────────────────

    fn write_char(&mut self, leaf: u8) {
        if self.bufpos == MATCH_MAX_LENGTH - 1 {
            let s = std::str::from_utf8(&self.buffer[..self.bufpos]).unwrap_or("");
            print!("{}", s);
            self.bufpos = 0;
            if leaf == b'\n' && self.bufpos > 0 && self.buffer[MATCH_MAX_LENGTH - 2] != b'\n' {
                self.buffer[self.bufpos] = leaf;
                self.bufpos += 1;
            }
        }
        if leaf == b'\n' {
            if self.bufpos > 0 && self.buffer[self.bufpos - 1] != b'\n' {
                self.buffer[self.bufpos] = leaf;
                self.bufpos += 1;
            }
        } else {
            self.buffer[self.bufpos] = leaf;
            self.bufpos += 1;
        }
    }

    fn expand_match(&mut self, leaf: u32, l: bool, r: bool) {
        if (leaf as usize) < ALPHABET_SIZE {
            if l || r {
                self.write_char(leaf as u8);
            }
            return;
        }
        if !self.automaton[leaf as usize].new_lines {
            if l || r {
                let lsym = self.grammar[leaf as usize].left_symbol;
                let rsym = self.grammar[leaf as usize].right_symbol;
                self.expand_match(lsym, l, r);
                self.expand_match(rsym, l, r);
            }
            return;
        }

        let lcount = self.automaton[self.grammar[leaf as usize].left_symbol as usize].count;
        let rcount = self.automaton[self.grammar[leaf as usize].right_symbol as usize].count;
        let self_count = self.automaton[leaf as usize].count;
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let lnl = self.automaton[lsym as usize].new_lines;
        let rnl = self.automaton[rsym as usize].new_lines;

        if lcount + rcount == self_count {
            // No new match at boundary
            if r {
                if !lnl {
                    self.expand_match(lsym, l, true);
                } else {
                    self.expand_match(lsym, l, false);
                }
            } else {
                self.expand_match(lsym, l, false);
            }
            if l {
                if !rnl {
                    self.expand_match(rsym, true, r);
                } else {
                    self.expand_match(rsym, false, r);
                }
            } else {
                self.expand_match(rsym, false, r);
            }
        } else {
            // New match at boundary
            self.expand_match(lsym, l, true);
            self.expand_match(rsym, true, r);
        }
    }

    fn expand_leaf_right(&mut self, leaf: u32) {
        if (leaf as usize) < ALPHABET_SIZE {
            self.write_char(leaf as u8);
            return;
        }
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let rnl = if (rsym as usize) >= self.num_rules as usize {
            self.automaton_seq[(rsym - self.num_rules) as usize].new_lines
        } else {
            self.automaton[rsym as usize].new_lines
        };
        if !rnl {
            self.expand_leaf_right(lsym);
            self.expand_leaf_right(rsym);
        } else {
            self.expand_leaf_right(rsym);
        }
    }

    fn expand_leaf_left(&mut self, leaf: u32) {
        if (leaf as usize) < ALPHABET_SIZE {
            self.write_char(leaf as u8);
            return;
        }
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let lnl = if (lsym as usize) >= self.num_rules as usize {
            self.automaton_seq[(lsym - self.num_rules) as usize].new_lines
        } else {
            self.automaton[lsym as usize].new_lines
        };
        if !lnl {
            self.expand_leaf_left(lsym);
            self.expand_leaf_left(rsym);
        } else {
            self.expand_leaf_left(lsym);
        }
    }

    // ── Output ────────────────────────────────────────────────────────────

    fn print_required_information(&mut self) {
        let axiom = self.num_rules as usize + self.automaton_seq.len() - 1;
        let ret: i64 = if self.mode != b'c' {
            let seq = &self.automaton_seq[axiom - self.num_rules as usize];
            if seq.match_ {
                let mut r = self.seq_counter as i64;
                if seq.left { r += 1; }
                if seq.right { r += 1; }
                if !seq.new_lines { r += 1; }
                r
            } else { 0 }
        } else {
            if self.tsrule.match_ {
                let mut r = self.seq_counter as i64;
                if self.tsrule.left { r += 1; }
                if self.tsrule.right { r += 1; }
                if !self.tsrule.new_lines { r += 1; }
                r
            } else { 0 }
        };

        if self.mode != b'c' {
            let buf = self.buffer[..self.bufpos].to_vec();
            let s = std::str::from_utf8(&buf).unwrap_or("");
            if s.ends_with('\n') {
                print!("{}", s);
            } else {
                println!("{}", s);
            }
        }

        if self.mode == b'c' || self.mode == b'a' {
            println!("{}", ret + self.counting_overflows as i64 * COUNTER_TOP as i64);
        }
    }
}

// ── Main search functions ─────────────────────────────────────────────────────

fn run_boolean_zearch(minimize: bool, data: &[u8], regex_str: &str) {
    // Parse header
    if data.len() < 12 {
        eprintln!("File too short");
        std::process::exit(-1);
    }
    let txt_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
    let num_rules = u32::from_le_bytes([data[4], data[5], data[6], data[7]]);
    let seq_len = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;
    let _ = txt_len;

    let mut state = ZearchState::new(num_rules, seq_len, b'b');
    state.initialize_automaton(minimize, regex_str);

    let mut bitin = BitIn::from_bytes(&data[12..]);
    let mut stack = Stack::new();

    let mut rules_counter = CHAR_SIZE as u32;
    let mut last_rule = num_rules;
    let mut flag = true;

    'outer: for _l in 0..seq_len {
        let mut exc: i32 = 0;
        let mut done = false;

        loop {
            let paren = bitin.read_bits(1);
            if paren == 1 {
                // OP
                exc += 1;
                let bits = 32 - rules_counter.leading_zeros();
                let read = bitin.read_bits(bits);
                stack.push(read);
                state.rule = read;
            } else {
                // CP
                exc -= 1;
                if exc == 0 && flag {
                    flag = false;
                    break;
                }

                state.right = stack.pop();
                state.left = stack.pop();

                if exc == 0 {
                    state.rule = last_rule;
                    last_rule += 1;
                    done = true;
                    stack.push(state.rule);
                    state.add_rule_seq_count();
                    if state.tsrule.match_ || state.tsrule.left || state.tsrule.right {
                        println!("MATCH");
                        return;
                    }
                } else {
                    rules_counter += 1;
                    state.rule = rules_counter;
                    stack.push(state.rule);
                    state.add_rule();
                    let trule = state.trule;
                    state.automaton[state.rule as usize] = trule;
                    if trule.count != 0 {
                        println!("MATCH");
                        return;
                    }
                }

                if done { break; }
            }
        }
    }

    println!("DOES NOT MATCH");
}

fn run_zearch(minimize: bool, data: &[u8], regex_str: &str, mode: u8) {
    // Parse header
    if data.len() < 12 {
        eprintln!("File too short");
        std::process::exit(-1);
    }
    let txt_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
    let num_rules = u32::from_le_bytes([data[4], data[5], data[6], data[7]]);
    let seq_len = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;
    let _ = txt_len;

    let mut state = ZearchState::new(num_rules, seq_len, mode);
    state.initialize_automaton(minimize, regex_str);

    let mut bitin = BitIn::from_bytes(&data[12..]);
    let mut stack = Stack::new();

    let mut rules_counter = CHAR_SIZE as u32;
    let mut last_rule = num_rules;
    let mut flag = true;
    let mut first_line = true;

    if mode != b'c' {
        for _l in (1..=seq_len).rev() {
            let mut exc: i32 = 0;
            let mut done = false;

            loop {
                let paren = bitin.read_bits(1);
                if paren == 1 {
                    // OP
                    exc += 1;
                    let bits = 32 - rules_counter.leading_zeros();
                    let read = bitin.read_bits(bits);
                    stack.push(read);
                    state.rule = read;
                } else {
                    // CP
                    exc -= 1;
                    if exc == 0 && flag {
                        // Leaf case
                        let rule = state.rule;
                        if state.automaton[rule as usize].left {
                            state.expand_leaf_left(rule);
                            first_line = false;
                        }
                        state.expand_match(rule, false, false);
                        if state.automaton[rule as usize].new_lines { first_line = false; }
                        flag = false;
                        break;
                    }

                    state.right = stack.pop();
                    state.left = stack.pop();
                    state.expand = false;

                    if exc == 0 {
                        state.rule = last_rule;
                        last_rule += 1;
                        done = true;
                        stack.push(state.rule);
                        state.add_rule_seq();
                        let rule = state.rule;
                        let nr = state.num_rules;
                        state.automaton_seq[(rule - nr) as usize] = state.tsrule;
                        state.grammar[rule as usize] = GrammarRule {
                            left_symbol: state.left,
                            right_symbol: state.right,
                        };

                        // First line handling
                        if first_line {
                            let left = state.left;
                            if (left as usize) >= state.num_rules as usize {
                                let seq = state.automaton_seq[(left - nr) as usize];
                                if seq.left {
                                    state.expand_leaf_left(left);
                                } else if seq.new_lines {
                                    first_line = false;
                                }
                            } else {
                                let a = state.automaton[left as usize];
                                if a.left {
                                    state.expand_leaf_left(left);
                                    first_line = false;
                                } else if a.new_lines {
                                    first_line = false;
                                }
                            }
                        }

                        if state.expand {
                            let left = state.left;
                            let right = state.right;
                            state.expand_leaf_right(left);
                            state.expand_leaf_left(right);
                        }

                        let right = state.right;
                        state.expand_match(right, false, false);
                        break;
                    } else {
                        rules_counter += 1;
                        state.rule = rules_counter;
                        stack.push(state.rule);
                        let lcount = state.automaton[state.left as usize].count;
                        let rcount = state.automaton[state.right as usize].count;
                        if COUNTER_TOP.wrapping_sub(lcount) <= rcount {
                            state.counting_overflows += 1;
                        }
                        state.add_rule();
                        let trule = state.trule;
                        let rule = state.rule;
                        let left = state.left;
                        let right = state.right;
                        state.automaton[rule as usize] = trule;
                        state.grammar[rule as usize] = GrammarRule { left_symbol: left, right_symbol: right };
                    }
                }
                if done { break; }
            }
        }
    } else {
        // Count-only mode
        for _l in (1..=seq_len).rev() {
            let mut exc: i32 = 0;
            let mut done = false;

            loop {
                let paren = bitin.read_bits(1);
                if paren == 1 {
                    // OP
                    exc += 1;
                    let bits = 32 - rules_counter.leading_zeros();
                    let read = bitin.read_bits(bits);
                    stack.push(read);
                    state.rule = read;
                } else {
                    // CP
                    exc -= 1;
                    if exc == 0 && flag {
                        flag = false;
                        break;
                    }

                    state.right = stack.pop();
                    state.left = stack.pop();
                    state.expand = false;

                    if exc == 0 {
                        state.rule = last_rule;
                        last_rule += 1;
                        done = true;
                        stack.push(state.rule);
                        state.add_rule_seq_count();
                        break;
                    } else {
                        rules_counter += 1;
                        state.rule = rules_counter;
                        stack.push(state.rule);
                        let lcount = state.automaton[state.left as usize].count;
                        let rcount = state.automaton[state.right as usize].count;
                        if COUNTER_TOP.wrapping_sub(lcount) <= rcount {
                            state.counting_overflows += 1;
                        }
                        state.add_rule();
                        let trule = state.trule;
                        state.automaton[state.rule as usize] = trule;
                    }
                }
                if done { break; }
            }
        }
    }

    state.print_required_information();
}

// ── Entry point ───────────────────────────────────────────────────────────────

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() <= 3 || args.len() >= 7 {
        eprintln!("Wrong arguments.");
        eprintln!("Usage: {} <option> <regex> <input_grammar>", args[0]);
        eprintln!("\nValues for <option>:");
        eprintln!("  -c: prints only the total number of matching lines");
        eprintln!("  -l: prints only the matching lines");
        eprintln!("  -a: c+l");
        eprintln!("  -b: prints MATCH or DOES NOT MATCH");
        std::process::exit(0);
    }

    let mut minimize = false;
    let mut mode = b'c';

    // Parse mode flag (second-to-last before file)
    if args[args.len()-3].starts_with('-') {
        let flag = args[args.len()-3].as_bytes()[1];
        mode = flag;
    }

    // Parse optional -m flag
    for i in 1..args.len()-3 {
        if args[i] == "-m" { minimize = true; }
    }

    if mode != b'a' && mode != b'c' && mode != b'l' && mode != b'b' {
        eprintln!("Invalid option. Using -c by default");
        mode = b'c';
    }

    let regex_str = &args[args.len()-2];
    let input_file = &args[args.len()-1];

    // Read the entire .rp file into memory
    let data = std::fs::read(input_file).unwrap_or_else(|e| {
        eprintln!("Error reading {}: {}", input_file, e);
        std::process::exit(-1);
    });

    if mode == b'b' {
        run_boolean_zearch(minimize, &data, regex_str);
    } else {
        run_zearch(minimize, &data, regex_str, mode);
    }
}
