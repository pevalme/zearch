/*
	Description: Implementation of counting.
	For the given rule X → AB, computes data for X based on information stored about A and B.

	Properties:
		- Matches across lines are not considered.

	Author: Pedro Valero
	Date: 12-17
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include "count.h"
#include "types.h"

extern int rule, left, right; // Rule under study
extern TRANSITION_FULL tleft, tright, trule; // Automaton elements related to rules under study
extern TRANSITION_SEQ tsleft, tsright, tsrule; // Automaton elements related to rules under study
extern int final_state; // Final state, guessed while translating the automaton
extern TRANSITION_FULL *automaton;
extern TRANSITION_SEQ *automaton_seq;
extern int seq_counter;
extern int seq_counter_new;
extern bool expand;

__attribute__((always_inline)) inline void incr_count_l1(int symbol) {
	automaton[symbol].match = 1;
	return;
}

__attribute__((always_inline)) inline void prop_count() {
	trule.match = 1;
	trule.count = tleft.count + tright.count;

	if (tleft.new_lines){
		trule.left = tleft.left;
		if (tright.new_lines) {
			trule.right = tright.right;
			trule.count += (tright.left || tleft.right);
			expand = (tright.left || tleft.right);
		} else {
			trule.right = tleft.right || tright.match;
		}
	} else {
		if (tright.new_lines) {
			trule.left = tright.left || tleft.match;
			trule.right = tright.right;
		}
	}
	return;
}

__attribute__((always_inline)) inline void incr_count() {
	trule.match = 1;
	trule.count = tleft.count + tright.count;

	if (tleft.new_lines){
		trule.left = tleft.left;
		if (tright.new_lines) {
			trule.right = tright.right;
			trule.count += 1;
			expand = 1;
		} else {
			trule.right = 1;
		}
	} else {
		if (tright.new_lines) {
			trule.left = 1;
			trule.right = tright.right;
		}
	}
	return;
}

__attribute__((always_inline)) inline void incr_count_seq_1(short middle) {
	tsrule.match = 1;
	seq_counter = tleft.count + tright.count;

	if (tleft.new_lines) {
		tsrule.left = tleft.left;
		if (tright.new_lines) {
			tsrule.right = tright.right;
			seq_counter += (tright.left || tleft.right || (middle == MIDDLE_STATE));
			expand = (tright.left || tleft.right || (middle == MIDDLE_STATE));
		} else {
			tsrule.right = tleft.right || tright.match || (middle == MIDDLE_STATE);
		}
	} else {
		if (tright.new_lines) {
			tsrule.left = tright.left || tleft.match || (middle == MIDDLE_STATE);
			tsrule.right = tright.right;
		}
	}
	return;
}

__attribute__((always_inline)) inline void prop_count_seq() {
	tsrule.match = 1;
	seq_counter_new = seq_counter + tright.count;

	if (__builtin_expect(tsleft.new_lines,1)) {
		tsrule.left = tsleft.left;
		if (tright.new_lines) {
			tsrule.right = tright.right;
			seq_counter_new += (tright.left || tsleft.right);
			expand = (tright.left || tsleft.right);
		} else {
			tsrule.right = tsleft.right || tright.match;
		}
	} else {
		if (tright.new_lines) {
			tsrule.left = tright.left || tsleft.match;
			tsrule.right = tright.right;
		}
	}
	return;
}

__attribute__((always_inline)) inline void incr_count_seq() {
	tsrule.match = 1;
	seq_counter_new = seq_counter + tright.count;

	if (__builtin_expect(tsleft.new_lines,1)) {
		tsrule.left = tsleft.left;
		if (tright.new_lines) {
			tsrule.right = tright.right;
			seq_counter_new += 1;
			expand = 1;
		} else {
			tsrule.right = 1;
		}
	} else {
		if (tright.new_lines) {
			tsrule.left = 1;
			tsrule.right = tright.right;
		}
	}
	return;
}