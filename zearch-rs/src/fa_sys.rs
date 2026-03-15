/// FFI bindings to libfa (from libaugeas)

use std::os::raw::{c_char, c_int, c_uchar};

/// Opaque type for a finite automaton
#[repr(C)]
pub struct Fa {
    _private: [u8; 0],
}

/// Opaque type for an automaton state
#[repr(C)]
pub struct State {
    _private: [u8; 0],
}

#[link(name = "fa")]
extern "C" {
    /// Compile a regular expression into an NFA
    pub fn fa_compile(re: *const c_char, size: usize, fa: *mut *mut Fa) -> c_int;

    /// Minimize the automaton in place
    pub fn fa_minimize(fa: *mut Fa) -> c_int;

    /// Free all memory used by the automaton
    pub fn fa_free(fa: *mut Fa);

    /// Return the initial state
    pub fn fa_state_initial(fa: *mut Fa) -> *mut State;

    /// Return true if the state is accepting
    pub fn fa_state_is_accepting(st: *mut State) -> bool;

    /// Return the next state in iteration order (NULL when done)
    pub fn fa_state_next(st: *mut State) -> *mut State;

    /// Return the number of transitions for a state
    pub fn fa_state_num_trans(st: *mut State) -> usize;

    /// Get details of the i-th transition
    pub fn fa_state_trans(
        st: *mut State,
        i: usize,
        to: *mut *mut State,
        min: *mut c_uchar,
        max: *mut c_uchar,
    ) -> c_int;
}
