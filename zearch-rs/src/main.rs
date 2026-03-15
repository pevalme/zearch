/*
 * zearch-rs: Rust reimplementation of zearch (algorithmically optimized)
 * Regular Expression Matching on Grammar-Compressed Text
 * (Ganty & Valero, DCC 2019)
 *
 * Optimizations over the C version:
 *  1. TransitionFull packed to 16 bytes (matching C bitfield layout)
 *  2. LTO + target-cpu=native (see .cargo/config.toml)
 *  3. recently_added resized to num_states×num_states after NFA init
 *     (reduces from 4MB to ~num_states²×4 bytes, fits in L1 cache)
 *  4. scratch_bitrow replaces edges[1024×1024] + num_edges[1024]:
 *     composition uses one u64 per state as a bitset instead of indexed
 *     arrays, reducing working set from 2MB to ≤ num_states×8 bytes
 *
 * License: GPL v3 (same as original C implementation)
 */

#![allow(clippy::needless_range_loop)]

mod fa_sys;

use fa_sys::*;

// ── Constants ─────────────────────────────────────────────────────────────────

const ALPHABET_SIZE: usize = 256;
const MAX_REGEX_SIZE: usize = 1024;
const SMALL_REGEX_BOUND: usize = 256;
const NUM_PAIRS_INITIAL: usize = 4;
const NUM_PAIRS_PER_STRUCT: usize = 2;
const COUNTER_TOP: u32 = 33_554_432; // 2^25
const MAX_PREALLOCATED: usize = 32768;
const CHAR_SIZE: usize = 256;
const MATCH_MAX_LENGTH: usize = 1000;

// ── TransitionFull packed bitfield ────────────────────────────────────────────
// Matches C's bitfield layout: count(25)|new_lines(1)|is_there(1)|match_(1)|right(1)|left(1)|pairs_used(2)
// Struct size = 4+4+2+2+4 = 16 bytes (identical to C)
const COUNT_MASK:  u32 = 0x01FF_FFFF;
const FLAG_NL:     u32 = 1 << 25;
const FLAG_IT:     u32 = 1 << 26;
const FLAG_MATCH:  u32 = 1 << 27;
const FLAG_RIGHT:  u32 = 1 << 28;
const FLAG_LEFT:   u32 = 1 << 29;
const PU_SHIFT:    u32 = 30;
const PU_MASK:     u32 = 3 << 30;

// ── Core data structures ──────────────────────────────────────────────────────

#[derive(Clone, Copy, Default)]
struct Pair {
    next_block: i16,
    next_index: i16,
    initial: [u8; NUM_PAIRS_PER_STRUCT],
    final_: [u8; NUM_PAIRS_PER_STRUCT],
}

/// 16-byte struct matching C's TRANSITION_FULL bitfield layout
#[derive(Clone, Copy, Default)]
struct TransitionFull {
    initial: [u8; NUM_PAIRS_INITIAL],
    final_: [u8; NUM_PAIRS_INITIAL],
    first_block: i16,
    first_index: i16,
    packed: u32,
}

impl TransitionFull {
    #[inline(always)] fn count(self) -> u32 { self.packed & COUNT_MASK }
    #[inline(always)] fn set_count(&mut self, v: u32) {
        self.packed = (self.packed & !COUNT_MASK) | (v & COUNT_MASK);
    }
    #[inline(always)] fn new_lines(self) -> bool { self.packed & FLAG_NL != 0 }
    #[inline(always)] fn set_new_lines(&mut self, v: bool) {
        if v { self.packed |= FLAG_NL; } else { self.packed &= !FLAG_NL; }
    }
    #[inline(always)] fn is_there(self) -> bool { self.packed & FLAG_IT != 0 }
    #[inline(always)] fn set_is_there(&mut self, v: bool) {
        if v { self.packed |= FLAG_IT; } else { self.packed &= !FLAG_IT; }
    }
    #[inline(always)] fn match_(self) -> bool { self.packed & FLAG_MATCH != 0 }
    #[inline(always)] fn set_match(&mut self, v: bool) {
        if v { self.packed |= FLAG_MATCH; } else { self.packed &= !FLAG_MATCH; }
    }
    #[inline(always)] fn right(self) -> bool { self.packed & FLAG_RIGHT != 0 }
    #[inline(always)] fn set_right(&mut self, v: bool) {
        if v { self.packed |= FLAG_RIGHT; } else { self.packed &= !FLAG_RIGHT; }
    }
    #[inline(always)] fn left(self) -> bool { self.packed & FLAG_LEFT != 0 }
    #[inline(always)] fn set_left(&mut self, v: bool) {
        if v { self.packed |= FLAG_LEFT; } else { self.packed &= !FLAG_LEFT; }
    }
    #[inline(always)] fn pairs_used(self) -> u8 { ((self.packed & PU_MASK) >> PU_SHIFT) as u8 }
    #[inline(always)] fn set_pairs_used(&mut self, v: u8) {
        self.packed = (self.packed & !PU_MASK) | ((v as u32 & 3) << PU_SHIFT);
    }
    fn empty() -> Self { TransitionFull { first_block: -1, first_index: -1, ..Default::default() } }
}

#[derive(Clone, Copy, Default)]
struct TransitionSeq {
    new_lines: bool,
    match_: bool,
    right: bool,
    left: bool,
}

#[derive(Clone, Copy, Default)]
struct GrammarRule {
    left_symbol: u32,
    right_symbol: u32,
}

// ── Memory allocator ──────────────────────────────────────────────────────────

struct Memory {
    blocks: Vec<Vec<Pair>>,
    num_pos: usize,
}

impl Memory {
    fn new() -> Self { Memory { blocks: Vec::new(), num_pos: MAX_PREALLOCATED } }

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
        unsafe { self.blocks.get_unchecked(block as usize).get_unchecked(index as usize) }
    }

    #[inline(always)]
    fn get_mut(&mut self, block: i16, index: i16) -> &mut Pair {
        unsafe { self.blocks.get_unchecked_mut(block as usize).get_unchecked_mut(index as usize) }
    }
}

// ── Bit reader ────────────────────────────────────────────────────────────────

struct BitIn {
    data: Vec<u32>,
    pos: usize,
    bitbuf: u32,
    bitlen: u32,
}

impl BitIn {
    fn from_bytes(bytes: &[u8]) -> Self {
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
        const W: u32 = 32;
        if rblen < self.bitlen {
            let x = self.bitbuf >> (W - rblen);
            self.bitbuf = self.bitbuf.wrapping_shl(rblen);
            self.bitlen -= rblen;
            x
        } else {
            let s = rblen - self.bitlen;
            let x = if self.bitlen + s == 0 { 0 }
                    else if s == 0 { self.bitbuf >> (W - self.bitlen) }
                    else { self.bitbuf >> (W - self.bitlen - s) };
            let word = if self.pos < self.data.len() { self.data[self.pos] } else { 0 };
            self.pos += 1;
            self.bitbuf = word;
            self.bitlen = W - s;
            if s != 0 {
                let result = x | (self.bitbuf >> self.bitlen);
                self.bitbuf = self.bitbuf.wrapping_shl(s);
                result
            } else { x }
        }
    }
}

// ── Stack ─────────────────────────────────────────────────────────────────────

struct Stack { data: Vec<u32> }

impl Stack {
    fn new() -> Self { Stack { data: Vec::with_capacity(1024) } }
    #[inline(always)] fn push(&mut self, v: u32) { self.data.push(v); }
    #[inline(always)] fn pop(&mut self) -> u32 { self.data.pop().expect("EMPTY STACK") }
}

// ── Main state struct ─────────────────────────────────────────────────────────

struct ZearchState {
    automaton: Vec<TransitionFull>,
    automaton_seq: Vec<TransitionSeq>,
    grammar: Vec<GrammarRule>,

    /// Dedup table: recently_added[i * ra_stride + f] = rule ID that last added edge (i→f).
    /// Resized to num_states × num_states after NFA init (stride = num_states).
    /// For a 10-state NFA: 400 bytes vs old 4MB — all in L1 cache.
    recently_added: Vec<i32>,
    ra_stride: usize,

    reached_states: [Vec<i32>; 2],
    rs_idx: usize,

    list_dots: Vec<u16>,
    dots: Vec<u8>,
    final_states: Vec<u8>,

    /// Bitrow scratch buffer for right-side composition.
    /// Layout: scratch_bitrow[state * bpr + word] where bpr = ceil(num_states/64).
    /// For a 10-state NFA: 10 u64s = 80 bytes vs old edges[1024×1024] = 2MB.
    scratch_bitrow: Vec<u64>,
    /// Number of u64 words per bitrow: ceil(num_states / 64)
    bpr: usize,

    num_states: usize,
    num_dots: usize,

    mem: Memory,
    num_rules: u32,
    counting_overflows: u32,
    seq_counter: i32,
    seq_counter_new: i32,

    rule: u32,
    left: u32,
    right: u32,

    tleft: TransitionFull,
    tright: TransitionFull,
    trule: TransitionFull,
    tsleft: TransitionSeq,
    tsrule: TransitionSeq,

    mode: u8,
    expand: bool,

    buffer: Vec<u8>,
    bufpos: usize,
}

impl ZearchState {
    fn new(num_rules: u32, seq_len: usize, mode: u8) -> Self {
        ZearchState {
            automaton: vec![TransitionFull::empty(); num_rules as usize],
            automaton_seq: if mode != b'c' && mode != b'b' {
                vec![TransitionSeq::default(); seq_len]
            } else { Vec::new() },
            grammar: if mode != b'c' && mode != b'b' {
                vec![GrammarRule::default(); num_rules as usize + seq_len]
            } else { Vec::new() },
            // Deferred: allocated in resize_after_automaton_init() to avoid 4MB zero-fill at startup
            recently_added: Vec::new(),
            ra_stride: 0,
            // Deferred: resized to num_states in resize_after_automaton_init()
            reached_states: [Vec::new(), Vec::new()],
            rs_idx: 0,
            list_dots: vec![0u16; MAX_REGEX_SIZE],
            dots: vec![0u8; MAX_REGEX_SIZE],
            final_states: vec![0u8; MAX_REGEX_SIZE],
            // Deferred: allocated in resize_after_automaton_init()
            scratch_bitrow: Vec::new(),
            bpr: 0,
            num_states: 0,
            num_dots: 0,
            mem: Memory::new(),
            num_rules,
            counting_overflows: 0,
            seq_counter: 0,
            seq_counter_new: 0,
            rule: 0, left: 0, right: 0,
            tleft: TransitionFull::empty(),
            tright: TransitionFull::empty(),
            trule: TransitionFull::empty(),
            tsleft: TransitionSeq::default(),
            tsrule: TransitionSeq::default(),
            mode,
            expand: false,
            buffer: vec![0u8; MATCH_MAX_LENGTH],
            bufpos: 0,
        }
    }

    /// Resize hot tables to num_states after NFA initialization.
    /// This shrinks recently_added from 4MB to num_states² bytes and
    /// scratch_bitrow from 8KB to num_states*bpr*8 bytes.
    fn resize_after_automaton_init(&mut self) {
        let ns = self.num_states;
        let bpr = (ns + 63) / 64;
        self.ra_stride = ns;
        self.recently_added = vec![0i32; ns * ns];
        self.bpr = bpr;
        self.scratch_bitrow = vec![0u64; ns * bpr];
        self.reached_states[0] = vec![-1i32; ns];
        self.reached_states[1] = vec![-1i32; ns];
        // Newlines generate new_lines
        self.automaton[10].set_new_lines(true);
        self.automaton[13].set_new_lines(true);
        // Initial state is always a dot state
        self.dots[0] = 1;
    }

    #[inline(always)]
    fn ra_get(&self, i: usize, f: usize) -> i32 {
        unsafe { *self.recently_added.get_unchecked(i * self.ra_stride + f) }
    }

    #[inline(always)]
    fn ra_set(&mut self, i: usize, f: usize, val: i32) {
        unsafe { *self.recently_added.get_unchecked_mut(i * self.ra_stride + f) = val; }
    }

    // ── NFA initialization (via libfa FFI) ────────────────────────────────

    fn initialize_automaton(&mut self, minimize: bool, regex: &str) {
        unsafe {
            let regex_cstr = std::ffi::CString::new(regex).unwrap();
            let mut fa_result: *mut Fa = std::ptr::null_mut();
            let ret = fa_compile(regex_cstr.as_ptr(), regex.len(), &mut fa_result);
            if ret != 0 { eprintln!("Error compiling regex: {}", ret); std::process::exit(-1); }
            if minimize { fa_minimize(fa_result); }

            let mut st = fa_state_initial(fa_result);
            if st.is_null() { eprintln!("Error: null initial state"); std::process::exit(-1); }

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
                    if st2 == st && begin == 0 && end == 9 {
                        let mut st3: *mut State = std::ptr::null_mut();
                        let mut begin2: u8 = 0;
                        let mut end2: u8 = 0;
                        if i + 1 < num_trans {
                            fa_state_trans(st, i + 1, &mut st3, &mut begin2, &mut end2);
                        }
                        if st3 == st && begin2 == 11 && end2 == 255 {
                            self.dots[from] = 1;
                            self.list_dots[self.num_dots] = from as u16;
                            self.num_dots += 1;
                            i += 2;
                            continue;
                        } else {
                            for r in 0u8..=9u8 {
                                self.rule = r as u32;
                                self.add_edge_direct_pre(from as u8, from as u8);
                            }
                            for r in begin2..=end2 {
                                self.rule = r as u32;
                                self.add_edge_direct_pre(from as u8, from as u8);
                            }
                        }
                    } else {
                        let to = hashes.iter().position(|&h| h == st2).unwrap_or(0);
                        for r in begin..=end {
                            self.rule = r as u32;
                            self.add_edge_direct_pre(from as u8, to as u8);
                            if from == 0 && self.final_states[to] != 0 {
                                self.automaton[r as usize].set_match(true);
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

        // Now that num_states is known, shrink hot tables
        self.resize_after_automaton_init();
    }

    // ── Edge addition ─────────────────────────────────────────────────────

    /// Used only during NFA init (before recently_added is resized).
    #[inline(always)]
    fn add_edge_direct_pre(&mut self, i: u8, f: u8) {
        let rule = self.rule as usize;
        if rule == 10 || rule == 13 { return; }
        // Use the full MAX_REGEX_SIZE stride (pre-resize)
        self.add_edge_direct_inner(i, f, rule);
    }

    fn add_edge_direct_inner(&mut self, i: u8, f: u8, rule: usize) {
        if !self.automaton[rule].is_there() {
            self.automaton[rule].set_is_there(true);
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                self.automaton[rule].set_pairs_used(0);
                let (block, index) = self.mem.malloc();
                self.automaton[rule].first_block = block;
                self.automaton[rule].first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
            } else {
                self.automaton[rule].first_block = -1;
                self.automaton[rule].first_index = -1;
                let pu = self.automaton[rule].pairs_used() as usize;
                self.automaton[rule].initial[pu] = i;
                self.automaton[rule].final_[pu] = f;
                self.automaton[rule].set_pairs_used(pu as u8 + 1);
            }
        } else if self.automaton[rule].pairs_used() == 0 {
            if self.automaton[rule].first_block == -1 {
                let (block, index) = self.mem.malloc();
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
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
                    p.initial[1] = i; p.final_[1] = f;
                } else {
                    let (nb, ni) = self.mem.malloc();
                    self.mem.get_mut(blk, idx).next_block = nb;
                    self.mem.get_mut(blk, idx).next_index = ni;
                    {
                        let p2 = self.mem.get_mut(nb, ni);
                        p2.initial[0] = i; p2.final_[0] = f; p2.next_block = -1; p2.next_index = -1;
                    }
                }
            }
        } else {
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                for it in self.automaton[rule].pairs_used() as usize..NUM_PAIRS_INITIAL {
                    self.automaton[rule].initial[it] = 0;
                    self.automaton[rule].final_[it] = 0;
                }
                self.automaton[rule].set_pairs_used(0);
                let (block, index) = self.mem.malloc();
                self.automaton[rule].first_block = block;
                self.automaton[rule].first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
            } else {
                let pu = self.automaton[rule].pairs_used() as usize;
                self.automaton[rule].initial[pu] = i;
                self.automaton[rule].final_[pu] = f;
                if pu == NUM_PAIRS_INITIAL - 1 {
                    self.automaton[rule].set_pairs_used(0);
                } else {
                    self.automaton[rule].set_pairs_used(pu as u8 + 1);
                }
            }
        }
    }

    #[inline(always)]
    fn add_edge(&mut self, i: u8, f: u8) {
        let rule = self.rule as i32;
        self.ra_set(i as usize, f as usize, rule);

        if !self.trule.is_there() {
            self.trule.set_is_there(true);
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                self.trule.set_pairs_used(0);
                self.trule.first_block = -1; self.trule.first_index = -1;
                let (block, index) = self.mem.malloc();
                self.trule.first_block = block; self.trule.first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
            } else {
                self.trule.first_block = -1; self.trule.first_index = -1;
                let pu = self.trule.pairs_used() as usize;
                self.trule.initial[pu] = i; self.trule.final_[pu] = f;
                self.trule.set_pairs_used(pu as u8 + 1);
            }
        } else if self.trule.pairs_used() == 0 {
            if self.trule.first_block == -1 {
                let (block, index) = self.mem.malloc();
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
                self.trule.first_block = block; self.trule.first_index = index;
            } else {
                let mut blk = self.trule.first_block; let mut idx = self.trule.first_index;
                loop {
                    let nb = self.mem.get(blk, idx).next_block;
                    let ni = self.mem.get(blk, idx).next_index;
                    if nb == -1 { break; }
                    blk = nb; idx = ni;
                }
                let p = self.mem.get_mut(blk, idx);
                if p.initial[1] == 0 && p.final_[1] == 0 {
                    p.initial[1] = i; p.final_[1] = f;
                } else {
                    let (nb, ni) = self.mem.malloc();
                    self.mem.get_mut(blk, idx).next_block = nb;
                    self.mem.get_mut(blk, idx).next_index = ni;
                    let p2 = self.mem.get_mut(nb, ni);
                    p2.initial[0] = i; p2.final_[0] = f; p2.next_block = -1; p2.next_index = -1;
                }
            }
        } else {
            if (f as usize) >= SMALL_REGEX_BOUND || (i as usize) >= SMALL_REGEX_BOUND {
                self.trule.set_pairs_used(0);
                let (block, index) = self.mem.malloc();
                self.trule.first_block = block; self.trule.first_index = index;
                let p = self.mem.get_mut(block, index);
                p.initial[0] = i; p.final_[0] = f; p.next_block = -1; p.next_index = -1;
            } else {
                let pu = self.trule.pairs_used() as usize;
                self.trule.initial[pu] = i; self.trule.final_[pu] = f;
                if pu == NUM_PAIRS_INITIAL - 1 {
                    self.trule.set_pairs_used(0);
                } else {
                    self.trule.set_pairs_used(pu as u8 + 1);
                }
            }
        }
    }

    // ── Counting functions ─────────────────────────────────────────────────

    #[inline(always)]
    fn prop_count(&mut self) {
        let tl = self.tleft; let tr = self.tright;
        self.trule.set_match(true);
        self.trule.set_count(tl.count().wrapping_add(tr.count()) & COUNT_MASK);
        if tl.new_lines() {
            self.trule.set_left(tl.left());
            if tr.new_lines() {
                self.trule.set_right(tr.right());
                let cross = tr.left() || tl.right();
                if cross { self.trule.set_count((self.trule.count().wrapping_add(1)) & COUNT_MASK); }
                self.expand = cross;
            } else { self.trule.set_right(tl.right() || tr.match_()); }
        } else if tr.new_lines() {
            self.trule.set_left(tr.left() || tl.match_());
            self.trule.set_right(tr.right());
        }
    }

    #[inline(always)]
    fn incr_count(&mut self) {
        let tl = self.tleft; let tr = self.tright;
        self.trule.set_match(true);
        self.trule.set_count(tl.count().wrapping_add(tr.count()) & COUNT_MASK);
        if tl.new_lines() {
            self.trule.set_left(tl.left());
            if tr.new_lines() {
                self.trule.set_right(tr.right());
                self.trule.set_count((self.trule.count().wrapping_add(1)) & COUNT_MASK);
                self.expand = true;
            } else { self.trule.set_right(true); }
        } else if tr.new_lines() {
            self.trule.set_left(true);
            self.trule.set_right(tr.right());
        }
    }

    #[inline(always)]
    fn prop_count_seq(&mut self) {
        let ts = self.tsleft; let tr = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter_new = self.seq_counter + tr.count() as i32;
        if ts.new_lines {
            self.tsrule.left = ts.left;
            if tr.new_lines() {
                self.tsrule.right = tr.right();
                let cross = tr.left() || ts.right;
                if cross { self.seq_counter_new += 1; }
                self.expand = cross;
            } else { self.tsrule.right = ts.right || tr.match_(); }
        } else if tr.new_lines() {
            self.tsrule.left = tr.left() || ts.match_;
            self.tsrule.right = tr.right();
        }
    }

    #[inline(always)]
    fn incr_count_seq(&mut self) {
        let ts = self.tsleft; let tr = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter_new = self.seq_counter + tr.count() as i32;
        if ts.new_lines {
            self.tsrule.left = ts.left;
            if tr.new_lines() {
                self.tsrule.right = tr.right();
                self.seq_counter_new += 1; self.expand = true;
            } else { self.tsrule.right = true; }
        } else if tr.new_lines() {
            self.tsrule.left = true;
            self.tsrule.right = tr.right();
        }
    }

    #[inline(always)]
    fn incr_count_seq_1(&mut self, middle_state: bool) {
        let tl = self.tleft; let tr = self.tright;
        self.tsrule.match_ = true;
        self.seq_counter = tl.count() as i32 + tr.count() as i32;
        if tl.new_lines() {
            self.tsrule.left = tl.left();
            if tr.new_lines() {
                self.tsrule.right = tr.right();
                let add = tr.left() || tl.right() || middle_state;
                if add { self.seq_counter += 1; }
                self.expand = add;
            } else { self.tsrule.right = tl.right() || tr.match_() || middle_state; }
        } else if tr.new_lines() {
            self.tsrule.left = tr.left() || tl.match_() || middle_state;
            self.tsrule.right = tr.right();
        }
    }

    // ── Saturation construction ────────────────────────────────────────────

    fn add_rule(&mut self) {
        let left = self.left as usize;
        let right = self.right as usize;
        let rule = self.rule as i32;

        self.tleft  = self.automaton[left];
        self.tright = self.automaton[right];
        self.trule  = TransitionFull::empty();
        self.expand = false;

        let tleft = self.tleft;
        let tright = self.tright;

        self.trule.set_new_lines(tleft.new_lines() || tright.new_lines());
        self.trule.set_match(false);
        self.trule.set_left(false);
        self.trule.set_right(false);

        if tright.match_() || tleft.match_() { self.prop_count(); }

        if !tleft.is_there() && !tright.is_there() { return; }

        // ── Case 1: only right transitions (or left has no outgoing) ──────
        if !tleft.is_there() || (tright.left() && !tleft.new_lines() && tright.is_there()) {
            if tright.right() { return; }
            if tleft.new_lines() {
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    if ini == 0 && s.final_states[fin as usize] == 0 {
                        if s.ra_get(0, fin as usize) != rule { s.add_edge(0, fin); }
                    }
                }, self);
            } else {
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    if s.dots[ini as usize] != 0 && (ini != 0 || s.final_states[fin as usize] == 0) {
                        if s.ra_get(ini as usize, fin as usize) != rule { s.add_edge(ini, fin); }
                    }
                }, self);
            }
            return;
        }

        // ── Case 2: compose left and right (main path) ─────────────────────
        if tright.is_there() && (!tleft.right() || tright.new_lines()) {
            // Build scratch_bitrow from right pairs.
            // scratch_bitrow[ini * bpr + (fin/64)] |= 1 << (fin%64)
            // This replaces the old edges[1024×1024] + num_edges[1024] tables.
            let bpr = self.bpr;
            let ns  = self.num_states;
            // Zero out scratch (ns * bpr u64s = typically 80 bytes for a 10-state NFA)
            self.scratch_bitrow.fill(0);

            let tright_nl = tright.new_lines();
            if tleft.new_lines() {
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    // Store in bitrow
                    unsafe {
                        let slot = s.scratch_bitrow.get_unchecked_mut(ini as usize * bpr + fin as usize / 64);
                        *slot |= 1u64 << (fin as usize % 64);
                    }
                    // Immediate add for state-0 edges
                    if ini == 0 && s.final_states[fin as usize] == 0 {
                        if s.ra_get(0, fin as usize) != rule { s.add_edge(0, fin); }
                    }
                }, self);
            } else {
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    unsafe {
                        let slot = s.scratch_bitrow.get_unchecked_mut(ini as usize * bpr + fin as usize / 64);
                        *slot |= 1u64 << (fin as usize % 64);
                    }
                    if s.dots[ini as usize] != 0 && (ini != 0 || s.final_states[fin as usize] == 0) {
                        if s.ra_get(ini as usize, fin as usize) != rule { s.add_edge(ini, fin); }
                    }
                }, self);
            }

            // Compose: for each left edge (ini → fin), iterate scratch_bitrow[fin]
            let mut mid = false;
            Self::iter_pairs(tleft, |ini, fin| (ini, fin), |s, ini, fin| {
                // Dot self-loop for fin
                if s.dots[fin as usize] != 0 && (s.final_states[fin as usize] != 0 || !tright_nl) {
                    if ini != 0 || s.final_states[fin as usize] == 0 {
                        if s.ra_get(ini as usize, fin as usize) != rule { s.add_edge(ini, fin); }
                    }
                }
                // Compose via bitrow
                unsafe {
                    let base = fin as usize * bpr;
                    for w in 0..bpr {
                        let mut bits = *s.scratch_bitrow.get_unchecked(base + w);
                        while bits != 0 {
                            let b = bits.trailing_zeros() as usize;
                            bits &= bits - 1;
                            let dest = (w * 64 + b) as u8;
                            if ini == 0 && s.final_states[dest as usize] != 0 {
                                mid |= fin != 0 && s.final_states[fin as usize] == 0;
                            } else {
                                if s.ra_get(ini as usize, dest as usize) != rule {
                                    s.add_edge(ini, dest);
                                }
                            }
                        }
                    }
                }
            }, self);

            if mid { self.incr_count(); }
            return;
        }

        // ── Case 3: only left transitions ─────────────────────────────────
        if tleft.left() { return; }
        if tright.new_lines() {
            Self::iter_pairs(tleft, |ini, fin| (ini, fin), |s, ini, fin| {
                if s.final_states[fin as usize] != 0 && ini != 0 {
                    if s.ra_get(ini as usize, fin as usize) != rule { s.add_edge(ini, fin); }
                }
            }, self);
        } else {
            Self::iter_pairs(tleft, |ini, fin| (ini, fin), |s, ini, fin| {
                if s.dots[fin as usize] != 0 && (ini != 0 || s.final_states[fin as usize] == 0) {
                    if s.ra_get(ini as usize, fin as usize) != rule { s.add_edge(ini, fin); }
                }
            }, self);
        }
    }

    /// Generic iterator over all (initial, final) pairs in a TransitionFull.
    /// Calls `callback(state, ini, fin)` for each pair.
    /// Using a free function (not a method closure) so the callback can take &mut Self.
    #[inline(always)]
    fn iter_pairs<F>(t: TransitionFull, _key: fn(u8, u8) -> (u8, u8), mut callback: F, s: &mut ZearchState)
    where F: FnMut(&mut ZearchState, u8, u8)
    {
        let npairs = if t.pairs_used() != 0 { t.pairs_used() as usize } else { NUM_PAIRS_INITIAL };
        for it in 0..npairs {
            callback(s, t.initial[it], t.final_[it]);
        }
        let mut blk = t.first_block;
        let mut idx = t.first_index;
        while blk != -1 {
            let pair = *s.mem.get(blk, idx);
            if pair.final_[0] == 0 { break; }
            for it in 0..NUM_PAIRS_PER_STRUCT {
                if pair.final_[it] == 0 { break; }
                callback(s, pair.initial[it], pair.final_[it]);
            }
            blk = pair.next_block;
            idx = pair.next_index;
        }
    }

    // ── Sequence rule processing ───────────────────────────────────────────

    fn add_rule_seq(&mut self) {
        let rule = self.rule;
        let left = self.left;
        let right = self.right;
        let num_rules = self.num_rules;
        let rs_cur = self.rs_idx;
        let rs_next = 1 - rs_cur;

        if rule > num_rules {
            self.tsleft = self.automaton_seq[(left - num_rules) as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();
            self.seq_counter_new = 0;

            let tright = self.tright;
            let tright_nl = tright.new_lines();
            self.tsrule.new_lines = self.tsleft.new_lines || tright_nl;
            let mut mid = false;

            if tright.is_there() {
                let left_i = left as i32;
                let rule_i = rule as i32;
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if s.reached_states[rs_cur][ini] == left_i {
                        s.reached_states[rs_next][fin] = rule_i;
                        mid |= s.final_states[fin] != 0 && ini != 0 && s.final_states[ini] == 0;
                    }
                }, self);
            }

            if !tright_nl {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_cur][ds] == left as i32 {
                        self.reached_states[rs_next][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_next;
            if mid { self.incr_count_seq(); }
            else if self.tsleft.match_ || self.tright.match_() { self.prop_count_seq(); }
            self.seq_counter = self.seq_counter_new;
            self.reached_states[self.rs_idx][0] = rule as i32;
        } else {
            self.tleft  = self.automaton[left as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();

            let tleft = self.tleft;
            let tright = self.tright;
            self.tsrule.new_lines = tleft.new_lines() || tright.new_lines();

            let rs_a = 0usize; let rs_b = 1usize;
            let mut mid = false; let mut added = false;

            if tleft.is_there() {
                let left_i = left as i32;
                Self::iter_pairs(tleft, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if ini == 0 || s.reached_states[rs_a][ini] == -1 {
                        s.reached_states[rs_a][fin] = left_i;
                        if s.final_states[fin] != 0 {
                            added = true;
                            mid |= fin != 0 && s.final_states[fin] == 0;
                        }
                    }
                }, self);
            }

            if tright.is_there() {
                let left_i = left as i32; let rule_i = rule as i32;
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if ini == 0 || s.reached_states[rs_a][ini] == left_i {
                        s.reached_states[rs_b][fin] = rule_i;
                        if s.final_states[fin] != 0 {
                            added = true;
                            mid |= ini != 0 && s.final_states[ini] == 0;
                        }
                    }
                }, self);
            }

            if !tright.new_lines() {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_a][ds] == left as i32 {
                        self.reached_states[rs_b][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_b;
            self.reached_states[self.rs_idx][0] = rule as i32;
            if mid { self.incr_count_seq_1(true); }
            else if tleft.match_() || tright.match_() || added { self.incr_count_seq_1(false); }
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
            self.tsleft = self.tsrule;
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();
            self.seq_counter_new = 0;

            let tright = self.tright;
            let tright_nl = tright.new_lines();
            self.tsrule.new_lines = self.tsleft.new_lines || tright_nl;

            if tright.right() && (self.tsleft.right || tright.left()) {
                self.incr_count_seq();
                self.reached_states[rs_next][0] = rule as i32;
                self.seq_counter = self.seq_counter_new;
                self.rs_idx = rs_next;
                self.reached_states[self.rs_idx][0] = rule as i32;
                return;
            }

            let mut mid = false;
            if tright.is_there() {
                let left_i = left as i32; let rule_i = rule as i32;
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if s.reached_states[rs_cur][ini] == left_i {
                        s.reached_states[rs_next][fin] = rule_i;
                        mid |= s.final_states[fin] != 0 && ini != 0 && s.final_states[ini] == 0;
                    }
                }, self);
            }

            if !tright_nl {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_cur][ds] == left as i32 {
                        self.reached_states[rs_next][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_next;
            if mid { self.incr_count_seq(); }
            else if self.tsleft.match_ || tright.match_() { self.prop_count_seq(); }
            self.seq_counter = self.seq_counter_new;
            self.reached_states[self.rs_idx][0] = rule as i32;
        } else {
            self.tleft  = self.automaton[left as usize];
            self.tright = self.automaton[right as usize];
            self.tsrule = TransitionSeq::default();

            let tleft = self.tleft;
            let tright = self.tright;
            self.tsrule.new_lines = tleft.new_lines() || tright.new_lines();

            let rs_a = 0usize; let rs_b = 1usize;
            let mut mid = false; let mut added = false;

            if tleft.is_there() {
                let left_i = left as i32;
                Self::iter_pairs(tleft, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if ini == 0 || s.reached_states[rs_a][ini] == -1 {
                        s.reached_states[rs_a][fin] = left_i;
                        if s.final_states[fin] != 0 {
                            added = true;
                            mid |= fin != 0 && s.final_states[fin] == 0;
                        }
                    }
                }, self);
            }

            if tright.is_there() {
                let left_i = left as i32; let rule_i = rule as i32;
                Self::iter_pairs(tright, |ini, fin| (ini, fin), |s, ini, fin| {
                    let (ini, fin) = (ini as usize, fin as usize);
                    if ini == 0 || s.reached_states[rs_a][ini] == left_i {
                        s.reached_states[rs_b][fin] = rule_i;
                        if s.final_states[fin] != 0 {
                            added = true;
                            mid |= ini != 0 && s.final_states[ini] == 0;
                        }
                    }
                }, self);
            }

            if !tright.new_lines() {
                for it in 0..self.num_dots {
                    let ds = self.list_dots[it] as usize;
                    if self.reached_states[rs_a][ds] == left as i32 {
                        self.reached_states[rs_b][ds] = rule as i32;
                    }
                }
            }

            self.rs_idx = rs_b;
            self.reached_states[self.rs_idx][0] = rule as i32;
            if mid { self.incr_count_seq_1(true); }
            else if tleft.match_() || tright.match_() || added { self.incr_count_seq_1(false); }
        }
    }

    // ── Match expansion ────────────────────────────────────────────────────

    fn write_char(&mut self, leaf: u8) {
        if self.bufpos == MATCH_MAX_LENGTH - 1 {
            let s = std::str::from_utf8(&self.buffer[..self.bufpos]).unwrap_or("");
            print!("{}", s);
            self.bufpos = 0;
        }
        if leaf == b'\n' {
            if self.bufpos > 0 && self.buffer[self.bufpos - 1] != b'\n' {
                self.buffer[self.bufpos] = leaf; self.bufpos += 1;
            }
        } else {
            self.buffer[self.bufpos] = leaf; self.bufpos += 1;
        }
    }

    fn expand_match(&mut self, leaf: u32, l: bool, r: bool) {
        if (leaf as usize) < ALPHABET_SIZE {
            if l || r { self.write_char(leaf as u8); }
            return;
        }
        if !self.automaton[leaf as usize].new_lines() {
            if l || r {
                let lsym = self.grammar[leaf as usize].left_symbol;
                let rsym = self.grammar[leaf as usize].right_symbol;
                self.expand_match(lsym, l, r); self.expand_match(rsym, l, r);
            }
            return;
        }
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let lcount = self.automaton[lsym as usize].count();
        let rcount = self.automaton[rsym as usize].count();
        let self_count = self.automaton[leaf as usize].count();
        let lnl = self.automaton[lsym as usize].new_lines();
        let rnl = self.automaton[rsym as usize].new_lines();
        if lcount + rcount == self_count {
            if r { if !lnl { self.expand_match(lsym, l, true); } else { self.expand_match(lsym, l, false); } }
            else { self.expand_match(lsym, l, false); }
            if l { if !rnl { self.expand_match(rsym, true, r); } else { self.expand_match(rsym, false, r); } }
            else { self.expand_match(rsym, false, r); }
        } else {
            self.expand_match(lsym, l, true); self.expand_match(rsym, true, r);
        }
    }

    fn expand_leaf_right(&mut self, leaf: u32) {
        if (leaf as usize) < ALPHABET_SIZE { self.write_char(leaf as u8); return; }
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let rnl = if (rsym as usize) >= self.num_rules as usize {
            self.automaton_seq[(rsym - self.num_rules) as usize].new_lines
        } else { self.automaton[rsym as usize].new_lines() };
        if !rnl { self.expand_leaf_right(lsym); self.expand_leaf_right(rsym); }
        else { self.expand_leaf_right(rsym); }
    }

    fn expand_leaf_left(&mut self, leaf: u32) {
        if (leaf as usize) < ALPHABET_SIZE { self.write_char(leaf as u8); return; }
        let lsym = self.grammar[leaf as usize].left_symbol;
        let rsym = self.grammar[leaf as usize].right_symbol;
        let lnl = if (lsym as usize) >= self.num_rules as usize {
            self.automaton_seq[(lsym - self.num_rules) as usize].new_lines
        } else { self.automaton[lsym as usize].new_lines() };
        if !lnl { self.expand_leaf_left(lsym); self.expand_leaf_left(rsym); }
        else { self.expand_leaf_left(lsym); }
    }

    // ── Output ─────────────────────────────────────────────────────────────

    fn print_required_information(&mut self) {
        let axiom = self.num_rules as usize + self.automaton_seq.len() - 1;
        let ret: i64 = if self.mode != b'c' {
            let seq = &self.automaton_seq[axiom - self.num_rules as usize];
            if seq.match_ {
                let mut r = self.seq_counter as i64;
                if seq.left { r += 1; } if seq.right { r += 1; }
                if !seq.new_lines { r += 1; } r
            } else { 0 }
        } else {
            if self.tsrule.match_ {
                let mut r = self.seq_counter as i64;
                if self.tsrule.left { r += 1; } if self.tsrule.right { r += 1; }
                if !self.tsrule.new_lines { r += 1; } r
            } else { 0 }
        };
        if self.mode != b'c' {
            let buf = self.buffer[..self.bufpos].to_vec();
            let s = std::str::from_utf8(&buf).unwrap_or("");
            if s.ends_with('\n') { print!("{}", s); } else { println!("{}", s); }
        }
        if self.mode == b'c' || self.mode == b'a' {
            println!("{}", ret + self.counting_overflows as i64 * COUNTER_TOP as i64);
        }
    }
}

// ── Main search functions ──────────────────────────────────────────────────────

fn run_boolean_zearch(minimize: bool, data: &[u8], regex_str: &str) {
    if data.len() < 12 { eprintln!("File too short"); std::process::exit(-1); }
    let num_rules = u32::from_le_bytes([data[4], data[5], data[6], data[7]]);
    let seq_len = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;

    let mut state = ZearchState::new(num_rules, seq_len, b'b');
    state.initialize_automaton(minimize, regex_str);

    let mut bitin = BitIn::from_bytes(&data[12..]);
    let mut stack = Stack::new();
    let mut rules_counter = CHAR_SIZE as u32;
    let mut last_rule = num_rules;
    let mut flag = true;

    for _l in 0..seq_len {
        let mut exc: i32 = 0;
        let mut done = false;
        loop {
            let paren = bitin.read_bits(1);
            if paren == 1 {
                exc += 1;
                let bits = 32 - rules_counter.leading_zeros();
                let read = bitin.read_bits(bits);
                stack.push(read); state.rule = read;
            } else {
                exc -= 1;
                if exc == 0 && flag { flag = false; break; }
                state.right = stack.pop(); state.left = stack.pop();
                if exc == 0 {
                    state.rule = last_rule; last_rule += 1; done = true;
                    stack.push(state.rule);
                    state.add_rule_seq_count();
                    if state.tsrule.match_ || state.tsrule.left || state.tsrule.right {
                        println!("MATCH"); return;
                    }
                } else {
                    rules_counter += 1; state.rule = rules_counter;
                    stack.push(state.rule);
                    state.add_rule();
                    let trule = state.trule;
                    state.automaton[state.rule as usize] = trule;
                    if trule.count() != 0 { println!("MATCH"); return; }
                }
                if done { break; }
            }
        }
    }
    println!("DOES NOT MATCH");
}

fn run_zearch(minimize: bool, data: &[u8], regex_str: &str, mode: u8) {
    if data.len() < 12 { eprintln!("File too short"); std::process::exit(-1); }
    let num_rules = u32::from_le_bytes([data[4], data[5], data[6], data[7]]);
    let seq_len = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;

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
                    exc += 1;
                    let bits = 32 - rules_counter.leading_zeros();
                    let read = bitin.read_bits(bits);
                    stack.push(read); state.rule = read;
                } else {
                    exc -= 1;
                    if exc == 0 && flag {
                        let rule = state.rule;
                        if state.automaton[rule as usize].left() { state.expand_leaf_left(rule); first_line = false; }
                        state.expand_match(rule, false, false);
                        if state.automaton[rule as usize].new_lines() { first_line = false; }
                        flag = false; break;
                    }
                    state.right = stack.pop(); state.left = stack.pop(); state.expand = false;
                    if exc == 0 {
                        state.rule = last_rule; last_rule += 1; done = true;
                        stack.push(state.rule);
                        state.add_rule_seq();
                        let rule = state.rule; let nr = state.num_rules;
                        state.automaton_seq[(rule - nr) as usize] = state.tsrule;
                        state.grammar[rule as usize] = GrammarRule { left_symbol: state.left, right_symbol: state.right };
                        if first_line {
                            let left = state.left;
                            if (left as usize) >= state.num_rules as usize {
                                let seq = state.automaton_seq[(left - nr) as usize];
                                if seq.left { state.expand_leaf_left(left); }
                                else if seq.new_lines { first_line = false; }
                            } else {
                                let a = state.automaton[left as usize];
                                if a.left() { state.expand_leaf_left(left); first_line = false; }
                                else if a.new_lines() { first_line = false; }
                            }
                        }
                        if state.expand {
                            let left = state.left; let right = state.right;
                            state.expand_leaf_right(left); state.expand_leaf_left(right);
                        }
                        let right = state.right; state.expand_match(right, false, false);
                        break;
                    } else {
                        rules_counter += 1; state.rule = rules_counter;
                        stack.push(state.rule);
                        let lcount = state.automaton[state.left as usize].count();
                        let rcount = state.automaton[state.right as usize].count();
                        if COUNTER_TOP.wrapping_sub(lcount) <= rcount { state.counting_overflows += 1; }
                        state.add_rule();
                        let trule = state.trule; let rule = state.rule;
                        let left = state.left; let right = state.right;
                        state.automaton[rule as usize] = trule;
                        state.grammar[rule as usize] = GrammarRule { left_symbol: left, right_symbol: right };
                    }
                }
                if done { break; }
            }
        }
    } else {
        for _l in (1..=seq_len).rev() {
            let mut exc: i32 = 0;
            let mut done = false;
            loop {
                let paren = bitin.read_bits(1);
                if paren == 1 {
                    exc += 1;
                    let bits = 32 - rules_counter.leading_zeros();
                    let read = bitin.read_bits(bits);
                    stack.push(read); state.rule = read;
                } else {
                    exc -= 1;
                    if exc == 0 && flag { flag = false; break; }
                    state.right = stack.pop(); state.left = stack.pop(); state.expand = false;
                    if exc == 0 {
                        state.rule = last_rule; last_rule += 1; done = true;
                        stack.push(state.rule);
                        state.add_rule_seq_count();
                        break;
                    } else {
                        rules_counter += 1; state.rule = rules_counter;
                        stack.push(state.rule);
                        let lcount = state.automaton[state.left as usize].count();
                        let rcount = state.automaton[state.right as usize].count();
                        if COUNTER_TOP.wrapping_sub(lcount) <= rcount { state.counting_overflows += 1; }
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

// ── Entry point ────────────────────────────────────────────────────────────────

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
    if args[args.len()-3].starts_with('-') { mode = args[args.len()-3].as_bytes()[1]; }
    for i in 1..args.len()-3 { if args[i] == "-m" { minimize = true; } }
    if mode != b'a' && mode != b'c' && mode != b'l' && mode != b'b' {
        eprintln!("Invalid option. Using -c by default"); mode = b'c';
    }

    let data = std::fs::read(&args[args.len()-1]).unwrap_or_else(|e| {
        eprintln!("Error reading {}: {}", args[args.len()-1], e); std::process::exit(-1);
    });

    if mode == b'b' { run_boolean_zearch(minimize, &data, &args[args.len()-2]); }
    else { run_zearch(minimize, &data, &args[args.len()-2], mode); }
}
