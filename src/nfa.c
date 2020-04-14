/*
	Description: Implementation of a Non deterministic Finite Automaton.

	This data structure is the core of ZEARCH and it is accessed from different modules, each one
	performing a different action. We have made it public (types.h) to simplify the implementation
	since modules "count" and "nfa" both handle it while being TODO

	typedef struct {
		unsigned char initial[NUM_PAIRS_INITIAL];
		unsigned char final[NUM_PAIRS_INITIAL];
		short first_block;
		short first_index;
		unsigned int count : 25; // This allow us to count, easily, up to 2**25 = 33554432
		unsigned char new_lines : 1; // Can be 0 or 1
		unsigned char is_there : 1;
		// Variables for counting
		unsigned char match : 1;
		unsigned char right : 1;
		unsigned char left : 1;
		unsigned char pairs_used : BITS_PAIRS_USED;
	} TRANSITION_FULL;

	Properties:
		* Implemented as an array of lists: automaton = TRANSITION_FULL[num_rules].
		* Each array corresponds to a variable in the grammar, which will label some transitions.
		* Each lists contains the pairs of states (q1, q2) connected by that label.
		* Uses count module to do the counting.
		* Includes operations required to perform the saturation construction.
		* It also stores, when needed, i.e. when matches are to be printed, the rules of the grammar.

	Author: Pedro Valero
	
	LICENSE: -zearch- Regular Expression Search on Compressed Text.
    Copyright (C) 2018 Pedro Valero & Pierre Ganty

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include "nfa.h"
#include "count.h"
#include "memory.h"
#include "types.h"
#include "mmintrin.h"

extern GRAMMAR_RULE *grammar;
extern TRANSITION_FULL *automaton;
extern TRANSITION_SEQ *automaton_seq;
extern int recently_added[MAX_REGEX_SIZE][MAX_REGEX_SIZE];
extern int reached_states[MAX_REGEX_SIZE];
extern int reached_states2[MAX_REGEX_SIZE];
extern short list_dots[MAX_REGEX_SIZE];
extern short dots[MAX_REGEX_SIZE];
extern short final_states[MAX_REGEX_SIZE];
extern short num_edges[MAX_REGEX_SIZE];
extern short edges[MAX_REGEX_SIZE][MAX_REGEX_SIZE]; // edges[q] is the list of states reachable from q
extern int *frequencies;
extern int *rs;
extern int *rs2;
extern unsigned int counting_overflows; // Number of times the counter has suffered an overflow.
extern unsigned int num_rules;
extern int seq_counter;
extern int seq_counter_new;
extern int final_state; // Final state, guessed while translating the automaton
extern int num_dots; // Number of dot states
extern int rule, left, right; // Rule under study
extern TRANSITION_FULL tleft, tright, trule; // Automaton elements related to rules under study
extern TRANSITION_SEQ tsleft, tsright, tsrule; // Automaton elements related to rules under study
extern TRANSITION_FULL tempty;
extern TRANSITION_SEQ tsempty;
extern int axiom; // Identifier of the axiom
extern int num_states; // Number of states of the NFA
extern char mode; // Chosen option

#ifdef STATS
extern long total_num_edges;
extern long used_pointers;
extern long bad_luck_counter;
extern long skipped;
extern long pskipped;
extern long no_connection_counter;
extern long qsskipped;
extern long wasted_memory;
extern long reinserted;
extern long num_operations_gr;
extern long num_operations_seq;

extern uint num_e_l;
extern uint num_e_r;

extern AVERAGE avg;
#endif

#ifdef PLOT
	extern int total_num_edges;
#endif

#define QUOTIENT 255
#define MULTIPLICATION 4294967296

void add_self_loop(int st) {
	dots[st] = 1;
	list_dots[num_dots++] = st;
	return;
}

void add_edge(short i, short f){
	PAIR *iter;
	int it;
	short block,index;

	DEBUG_PRINT("Adding %d-%d- (%hd, %hd)\n", rule, trule.pairs_used, i, f);

#ifdef STATS
	total_num_edges++;
#endif
#ifdef PLOT
	total_num_edges++;
#endif

	recently_added[i][f] = rule;

	if (trule.is_there == 0) { // First edge with label=rule
		DEBUG_PRINT("First time symbol is added\n");
		if (__builtin_expect((f >= SMALL_REGEX_BOUND || i >= SMALL_REGEX_BOUND),0)) {
			trule.is_there = 1;
			memory_malloc(&block, &index);
			trule.first_block = block;
			trule.first_index = index;
			iter = memory_get(block, index);
			iter->initial[0] = i;
			iter->final[0] = f;
			iter->next_block = -1;
			iter->next_index = -1;
#ifdef STATS
			used_pointers++;
			wasted_memory++;
#endif
		} else {
			trule.is_there = 1;
			trule.initial[trule.pairs_used] = i;
			trule.final[trule.pairs_used] = f;
			trule.first_block = -1;
			trule.first_index = -1;
			trule.pairs_used++;
#ifdef STATS
#endif
		}
	} else {
		DEBUG_PRINT("Not first time\n");
		if (trule.pairs_used == 0) {
			if (trule.first_block == -1) {
				memory_malloc(&block, &index);
				trule.first_block = block;
				trule.first_index = index;
				iter = memory_get(block, index);
				iter->initial[0] = i;
				iter->final[0] = f;
				iter->next_block = -1;
				iter->next_index = -1;
#ifdef STATS
				used_pointers++;
#endif
			} else {
				iter = memory_get(trule.first_block, trule.first_index);
				while (iter->next_block != -1) iter = memory_get(iter->next_block, iter->next_index);

				if (iter->initial[1] == 0 && iter->final[1] == 0) {
					iter->initial[1] = i;
					iter->final[1] = f;
				} else {
					memory_malloc(&(iter->next_block), &(iter->next_index));
					iter = memory_get(iter->next_block, iter->next_index);
					iter->initial[0] = i;
					iter->final[0] = f;
					iter->next_block = -1;
					iter->next_index = -1;
#ifdef STATS
					used_pointers++;
#endif
				}
			}
		} else {
			DEBUG_PRINT("Space available in array\n");
			if (__builtin_expect((f >= SMALL_REGEX_BOUND || i >= SMALL_REGEX_BOUND),0)) {
				trule.pairs_used = 0;
				memory_malloc(&block, &index);
				trule.first_block = block;
				trule.first_index = index;
				iter = memory_get(block, index);
				iter->initial[0] = i;
				iter->final[0] = f;
				iter->next_block = -1;
				iter->next_index = -1;
#ifdef STATS
				used_pointers++;
				wasted_memory++;
#endif
			} else {
				trule.initial[trule.pairs_used] = i;
				trule.final[trule.pairs_used] = f;
				if (trule.pairs_used == NUM_PAIRS_INITIAL - 1) trule.pairs_used = 0;
				else trule.pairs_used++;
			}
		}
	}
}

void add_edge_direct(short i, short f){
	PAIR *iter;
	int it;
	short block,index;

	DEBUG_PRINT("Adding %d-%d- (%hd, %hd)\n", rule, automaton[rule].pairs_used, i, f);
#ifdef STATS
	total_num_edges++;
#endif
#ifdef PLOT
	total_num_edges++;
#endif
	if (rule == 10 || rule == 13) return;
	if (automaton[rule].is_there == 0) { // First edge with label=rule
		DEBUG_PRINT("First time symbol is added\n");
		if (__builtin_expect((f >= SMALL_REGEX_BOUND || i >= SMALL_REGEX_BOUND),0)) {
			automaton[rule].is_there = 1;
			automaton[rule].pairs_used = 0;
			memory_malloc(&block, &index);
			automaton[rule].first_block = block;
			automaton[rule].first_index = index;
			iter = memory_get(block, index);
			iter->initial[0] = i;
			iter->final[0] = f;
			iter->next_block = -1;
			iter->next_index = -1;
#ifdef STATS
			used_pointers++;
			wasted_memory++;
#endif
		} else {
			automaton[rule].is_there = 1;
			automaton[rule].initial[automaton[rule].pairs_used] = i;
			automaton[rule].final[automaton[rule].pairs_used] = f;
			automaton[rule].first_block = -1;
			automaton[rule].first_index = -1;
			automaton[rule].pairs_used++;
		}
	} else {
		if (automaton[rule].pairs_used == 0) {
			if (automaton[rule].first_block == -1) {
				memory_malloc(&block, &index);
				automaton[rule].first_block = block;
				automaton[rule].first_index = index;
				iter = memory_get(block, index);
				iter->initial[0] = i;
				iter->final[0] = f;
				iter->next_block = -1;
				iter->next_index = -1;
#ifdef STATS
				used_pointers++;
#endif
			} else {
				iter = memory_get(automaton[rule].first_block, automaton[rule].first_index);
				while (iter->next_block != -1) iter = memory_get(iter->next_block, iter->next_index);

				if (iter->initial[1] == 0 && iter->final[1] == 0) {
					iter->initial[1] = i;
					iter->final[1] = f;
				} else {
					memory_malloc(&(iter->next_block), &(iter->next_index));
					iter = memory_get(iter->next_block, iter->next_index);
					iter->initial[0] = i;
					iter->final[0] = f;
					recently_added[i][f] = rule;
					iter->next_block = -1;
					iter->next_index = -1;
#ifdef STATS
					used_pointers++;
#endif
				}
			}
		} else {

			if (__builtin_expect((f >= SMALL_REGEX_BOUND || i >= SMALL_REGEX_BOUND),0)) {
				for (it = automaton[rule].pairs_used; it < NUM_PAIRS_INITIAL; it++) {
					automaton[rule].initial[it] = 0;
					automaton[rule].final[it] = 0;
				}
				automaton[rule].pairs_used = 0;
				memory_malloc(&block, &index);
				automaton[rule].first_block = block;
				automaton[rule].first_index = index;
				iter = memory_get(block, index);
				iter->initial[0] = i;
				iter->final[0] = f;
				iter->next_block = -1;
				iter->next_index = -1;
#ifdef STATS
				used_pointers++;
				wasted_memory++;
#endif
			} else {
				automaton[rule].initial[automaton[rule].pairs_used] = i;
				automaton[rule].final[automaton[rule].pairs_used] = f;
				if (automaton[rule].pairs_used == NUM_PAIRS_INITIAL - 1) automaton[rule].pairs_used = 0;
				else automaton[rule].pairs_used++;
			}
		}
	}
}

void add_rule(){
	PAIR pleft, pright;
	int it, it2; // Iterators over the pairs grouped in a PAIR structure
	int i;
	bool bad_luck; // When bad_luck is 1 it means the automaton is not deterministic and the improvement given by edges does not apply.
	char rpairs, lpairs;
	char mid = 0, added = 0;

#ifdef STATS	
	num_e_r=0;
	num_e_l=0;
#endif	

	tleft = automaton[left];
	tright = automaton[right];
	trule = tempty;

	// Propagate
	trule.new_lines = tleft.new_lines || tright.new_lines;

	// Default values
	trule.match = 0;
	trule.left = 0;
	trule.right = 0;

	DEBUG_PRINT("1Looking at: %d (%d) → %d (%d) %d (%d)\n", rule, trule.new_lines, left, tleft.new_lines, right, tright.new_lines);

	if (tright.match || tleft.match) prop_count();

	if (tleft.is_there == 0 && tright.is_there == 0) {
#ifdef STATS
		skipped++;
#endif
		return;
	}

#ifdef STATS
	num_e_l = 0;
	num_e_r = 0;
	if (tleft.is_there != 0) {
		iterate_left(it, num_e_l++;, num_e_l++;)
	}

	if (tright.is_there != 0) {
		iterate_right(it, num_e_r++;, num_e_r++;)
	}
#endif

	if (tleft.is_there == 0 || (tright.left && tleft.new_lines == 0 && tright.is_there)) {
		if (tright.right) return;
#ifdef STATS
		num_operations_gr += num_e_r;
#endif
		if (tleft.new_lines) {
			iterate_right(it, \
				if (tright.initial[it] == 0 && !final_states[tright.final[it]]){ \
					if (recently_added[0][tright.final[it]] != rule) add_edge(0,tright.final[it]); \
				}, \
				if (pright.initial[it] == 0 && !final_states[pright.final[it]]){ \
					if (recently_added[0][pright.final[it]] != rule) add_edge(0,pright.final[it]); \
				} \
			)
		} else {
			iterate_right(it, \
				if (dots[tright.initial[it]] && (tright.initial[it] != 0 || !final_states[tright.final[it]])){ \
					if (recently_added[tright.initial[it]][tright.final[it]] != rule) add_edge(tright.initial[it],tright.final[it]); \
				}, \
				if (dots[pright.initial[it]] && (pright.initial[it] != 0 || !final_states[pright.final[it]])){ \
					if (recently_added[pright.initial[it]][pright.final[it]] != rule) add_edge(pright.initial[it],pright.final[it]); \
				} \
			)
	}

#ifdef STATS
		pskipped++;
#endif
		return;
	}

	if (tright.is_there && (tleft.right == 0 || tright.new_lines != 0)) {
		memset(num_edges, 0, sizeof(short) * num_states);
		#ifdef STATS
		num_operations_gr += num_states;
		#endif
		if (tleft.new_lines) {
			iterate_right(it, \
				edges[tright.initial[it]][num_edges[tright.initial[it]]++] = tright.final[it]; \
				if (tright.initial[it] == 0 && !final_states[tright.final[it]]){ \
					if (recently_added[tright.initial[it]][tright.final[it]] != rule) add_edge(tright.initial[it],tright.final[it]); \
				}, \
				edges[pright.initial[it]][num_edges[pright.initial[it]]++] = pright.final[it]; \
				if (pright.initial[it] == 0 && !final_states[pright.final[it]]){ \
					if (recently_added[pright.initial[it]][pright.final[it]] != rule) add_edge(pright.initial[it],pright.final[it]); \
				} \
			)
		} else {
			iterate_right(it, \
				edges[tright.initial[it]][num_edges[tright.initial[it]]++] = tright.final[it]; \
				if (dots[tright.initial[it]] && (tright.initial[it] != 0 || !final_states[tright.final[it]])){ \
					if (recently_added[tright.initial[it]][tright.final[it]] != rule) add_edge(tright.initial[it],tright.final[it]); \
				}, \
				edges[pright.initial[it]][num_edges[pright.initial[it]]++] = pright.final[it]; \
				if (dots[pright.initial[it]] && (pright.initial[it] != 0 || !final_states[pright.final[it]])){ \
					if (recently_added[pright.initial[it]][pright.final[it]] != rule) add_edge(pright.initial[it],pright.final[it]); \
				} \
			)
		}

#ifdef STATS
		num_operations_gr += num_e_r;
		iterate_left(it, num_operations_gr += 1 + num_edges[tleft.final[it]];, num_operations_gr += 1 + num_edges[pleft.final[it]];)
#endif
		iterate_left(it, \
			if (dots[tleft.final[it]] && (final_states[tleft.final[it]] || tright.new_lines == 0)){ \
				if (tleft.initial[it] != 0 || !final_states[tleft.final[it]]) { \
					if (recently_added[tleft.initial[it]][tleft.final[it]] != rule) add_edge(tleft.initial[it],tleft.final[it]); \
				} \
			} \
			for (i = 0; i < num_edges[tleft.final[it]]; i++) { \
				if (tleft.initial[it] == 0 && final_states[edges[tleft.final[it]][i]]) { \
					mid |= (tleft.final[it] && !final_states[tleft.final[it]]); \
				} else {\
					if (recently_added[tleft.initial[it]][edges[tleft.final[it]][i]] != rule) add_edge(tleft.initial[it], edges[tleft.final[it]][i]); \
				} \
			}, \
			if (dots[pleft.final[it]] && (final_states[pleft.final[it]] || tright.new_lines == 0)){ \
				if (pleft.initial[it] != 0 || !final_states[pleft.final[it]]) { \
					if (recently_added[pleft.initial[it]][pleft.final[it]] != rule) add_edge(pleft.initial[it],pleft.final[it]); \
				} \
			} \
			for (i = 0; i < num_edges[pleft.final[it]]; i++) { \
				if (pleft.initial[it] == 0 && final_states[edges[pleft.final[it]][i]]) { \
					mid |= (pleft.final[it] && !final_states[pleft.final[it]]); \
				} else {\
					if (recently_added[pleft.initial[it]][edges[pleft.final[it]][i]] != rule) add_edge(pleft.initial[it], edges[pleft.final[it]][i]); \
				} \
			}
		)

		if (mid) incr_count();

		return;
	}
	// There is no transition labeled with right
	if (tleft.left) return;
#ifdef STATS
		num_operations_gr += num_e_l;
#endif
	if (tright.new_lines) {
		iterate_left (it, \
			if (final_states[tleft.final[it]] && tleft.initial[it] != 0){ \
				if (recently_added[tleft.initial[it]][tleft.final[it]] != rule) add_edge(tleft.initial[it],tleft.final[it]); \
			}, \
			if (final_states[pleft.final[it]] && pleft.initial[it] != 0){ \
				if (recently_added[pleft.initial[it]][pleft.final[it]] != rule) add_edge(pleft.initial[it],pleft.final[it]); \
			} \
		)
	} else {
		iterate_left (it, \
			if (dots[tleft.final[it]] && (tleft.initial[it] != 0 || !final_states[tleft.final[it]])){ \
				if (recently_added[tleft.initial[it]][tleft.final[it]] != rule) add_edge(tleft.initial[it],tleft.final[it]); \
			}, \
			if (dots[pleft.final[it]] && (pleft.initial[it] != 0 || !final_states[pleft.final[it]])){ \
				if (recently_added[pleft.initial[it]][pleft.final[it]] != rule) add_edge(pleft.initial[it],pleft.final[it]); \
			} \
		)
	}
#ifdef STATS
	pskipped++;
#endif

	return;
}

void add_rule_seq(){
	int *rsaux;
	PAIR pleft, pright;
	int it; // Iterators over the pairs grouped in a PAIR structure
	char rpairs, lpairs;
	char mid = 0, added = 0;

	if (__builtin_expect(rule > num_rules,1)) {
		tsleft = automaton_seq[left-num_rules];
		tright = automaton[right];
		tsrule = tsempty;
		seq_counter_new = 0;

		// Propagate
		tsrule.new_lines = tsleft.new_lines || tright.new_lines;

		DEBUG_PRINT("2Looking at: %d (%d) → %d (%d) %d (%d)\n", rule, tsrule.new_lines, left, tsleft.new_lines, right, tright.new_lines);

		if (tright.is_there) {
			iterate_right(it, \
				if (rs[tright.initial[it]] == left) { \
					rs2[tright.final[it]] = rule; \
					mid |= (final_states[tright.final[it]] && tright.initial[it] && !final_states[tright.initial[it]]); \
				}, \
				if (rs[pright.initial[it]] == left) { \
					rs2[pright.final[it]] = rule; \
					mid |= (final_states[pright.final[it]] && pright.initial[it] && !final_states[pright.initial[it]]); \
				} \
			)
		}
#ifdef STATS
		if (tright.is_there == 0) qsskipped++;
		else {
			iterate_right(it, num_operations_seq++;, num_operations_seq++;)
		}
#endif

		if (tright.new_lines == 0) {
			for (it = 0; it < num_dots; it++){
				if (rs[list_dots[it]] == left) rs2[list_dots[it]] = rule;
			}
		}

		rsaux = rs;
		rs = rs2;
		rs2 = rsaux;

		if (mid) incr_count_seq();
		else if (tsleft.match || tright.match) prop_count_seq();

		seq_counter = seq_counter_new;

		rs[0] = rule;
		return;
	} else {
		tleft = automaton[left];
		tright = automaton[right];
		tsrule = tsempty;

		// Propagate
		tsrule.new_lines = tleft.new_lines || tright.new_lines;

		DEBUG_PRINT("3Looking at: %d (%d) → %d (%d) %d (%d)\n", rule, tsrule.new_lines, left, tleft.new_lines, right, tright.new_lines);

#ifdef STATS
	num_e_r = 0;
	num_e_l = 0;
	if (tleft.is_there != 0) {
		iterate_left(it, num_e_l++;, num_e_l++;)
	}

	if (tright.is_there != 0) {
		iterate_right(it, num_e_r++;, num_e_r++;)
	}

	num_operations_seq += num_e_l*num_e_r;
#endif

		rs = reached_states;
		if (tleft.is_there) {
			iterate_left(it, \
				if (tleft.initial[it] == 0 || rs[tleft.initial[it]] == -1) { \
					DEBUG_PRINT("Reachable %d\n", it);
					rs[tleft.final[it]] = left; \
					if (final_states[tleft.final[it]]) { \
						added = 1; \
						mid |= (tleft.final[it] && !final_states[tleft.final[it]]); \
					}\
				}, \
				if (pleft.initial[it] == 0 || rs[pleft.initial[it]] == -1) { \
					rs[pleft.final[it]] = left; \
					if (final_states[pleft.final[it]]) { \
						added = 1; \
						mid |= (pleft.final[it] && !final_states[pleft.final[it]]); \
					}\
				} \
			)
		}

		rs2 = reached_states2;

		if (tright.is_there) {
			iterate_right(it, \
				if (tright.initial[it] == 0 || rs[tright.initial[it]] == left) { \
					rs2[tright.final[it]] = rule; \
					if (final_states[tright.final[it]]) { \
						added = 1; \
						mid |= (tright.initial[it] && !final_states[tright.initial[it]]); \
					}\
				}, \
				if (pright.initial[it] == 0 || rs[pright.initial[it]] == left) { \
					rs2[pright.final[it]] = rule; \
					if (final_states[pright.final[it]]) { \
						added = 1; \
						mid |= (pright.initial[it] && !final_states[pright.initial[it]]); \
					}\
				} \
			)
		}

		if (tright.new_lines == 0) {
			for (it = 0; it < num_dots; it++){
				if (rs[list_dots[it]] == left) rs2[list_dots[it]] = rule;
			}
		}

		rs = reached_states2;
		rs2 = reached_states;

		rs[0] = rule;

		if (mid) incr_count_seq_1(MIDDLE_STATE);
		else if (tleft.match || tright.match || added) incr_count_seq_1(INITIAL_FINAL_STATE);
		return;
	}
}

void add_rule_seq_count(){
	int *rsaux;
	PAIR pleft, pright;
	int it; // Iterators over the pairs grouped in a PAIR structure
	char rpairs, lpairs;
	char mid = 0, added = 0;

	if (__builtin_expect(rule > num_rules,1)) {
		tsleft = tsrule;
		tright = automaton[right];
		tsrule = tsempty;
		seq_counter_new = 0;

		// Propagate
		tsrule.new_lines = tsleft.new_lines || tright.new_lines;

		DEBUG_PRINT("2Looking at: %d (%d) → %d (%d) %d (%d)\n", rule, tsrule.new_lines, left, tsleft.new_lines, right, tright.new_lines);

		if (tright.is_there) {
			if (tright.right && (tsleft.right || tright.left)) {
				incr_count_seq();
				rs2[final_state] = rule;
				seq_counter = seq_counter_new;
				rsaux = rs;
				rs = rs2;
				rs2 = rsaux;
				rs[0] = rule;
				return;
			}

			iterate_right(it, \
				if (rs[tright.initial[it]] == left) { \
					rs2[tright.final[it]] = rule; \
					mid |= (final_states[tright.final[it]] && tright.initial[it] && !final_states[tright.initial[it]]); \
				}, \
				if (rs[pright.initial[it]] == left) { \
					rs2[pright.final[it]] = rule; \
					mid |= (final_states[pright.final[it]] && pright.initial[it] && !final_states[pright.initial[it]]); \
				} \
			)
		}
#ifdef STATS
		if (tright.is_there == 0) qsskipped++;
		else {
			iterate_right(it, num_operations_seq++;, num_operations_seq++;)
		}
#endif

		if (tright.new_lines == 0) {
			for (it = 0; it < num_dots; it++){
				if (rs[list_dots[it]] == left) rs2[list_dots[it]] = rule;
			}
		}

		rsaux = rs;
		rs = rs2;
		rs2 = rsaux;

		if (mid) incr_count_seq();
		else if (tsleft.match || tright.match) prop_count_seq();

		seq_counter = seq_counter_new;

		rs[0] = rule;
		return;
	} else {
		tleft = automaton[left];
		tright = automaton[right];
		tsrule = tsempty;

		// Propagate
		tsrule.new_lines = tleft.new_lines || tright.new_lines;

		DEBUG_PRINT("3Looking at: %d (%d) → %d (%d) %d (%d)\n", rule, tsrule.new_lines, left, tleft.new_lines, right, tright.new_lines);

#ifdef STATS
	num_e_r = 0;
	num_e_l = 0;
	if (tleft.is_there != 0) {
		iterate_left(it, num_e_l++;, num_e_l++;)
	}

	if (tright.is_there != 0) {
		iterate_right(it, num_e_r++;, num_e_r++;)
	}

	num_operations_seq += num_e_l*num_e_r;
#endif

		rs = reached_states;
		if (tleft.is_there) {
			iterate_left(it, \
				if (tleft.initial[it] == 0 || rs[tleft.initial[it]] == -1) { \
					DEBUG_PRINT("Reachable %d\n", it);
					rs[tleft.final[it]] = left; \
					if (final_states[tleft.final[it]]) { \
						added = 1; \
						mid |= (tleft.final[it] && !final_states[tleft.final[it]]); \
					}\
				}, \
				if (pleft.initial[it] == 0 || rs[pleft.initial[it]] == -1) { \
					rs[pleft.final[it]] = left; \
					if (final_states[pleft.final[it]]) { \
						added = 1; \
						mid |= (pleft.final[it] && !final_states[pleft.final[it]]); \
					}\
				} \
			)
		}

		rs2 = reached_states2;

		if (tright.is_there) {
			iterate_right(it, \
				if (tright.initial[it] == 0 || rs[tright.initial[it]] == left) { \
					rs2[tright.final[it]] = rule; \
					if (final_states[tright.final[it]]) { \
						added = 1; \
						mid |= (tright.initial[it] && !final_states[tright.initial[it]]); \
					}\
				}, \
				if (pright.initial[it] == 0 || rs[pright.initial[it]] == left) { \
					rs2[pright.final[it]] = rule; \
					if (final_states[pright.final[it]]) { \
						added = 1; \
						mid |= (pright.initial[it] && !final_states[pright.initial[it]]); \
					}\
				} \
			)
		}

		if (tright.new_lines == 0) {
			for (it = 0; it < num_dots; it++){
				if (rs[list_dots[it]] == left) rs2[list_dots[it]] = rule;
			}
		}

		rs = reached_states2;
		rs2 = reached_states;

		rs[0] = rule;

		if (mid) incr_count_seq_1(MIDDLE_STATE);
		else if (tleft.match || tright.match || added) incr_count_seq_1(INITIAL_FINAL_STATE);
		return;
	}
}

void free_automaton(){
	free(automaton);
	free(automaton_seq);
	memory_free();
	free(grammar);
}
