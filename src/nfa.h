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
		unsigned int count : 24; // This allow us to count, easily, up to 2**24 = 16777216
		unsigned char new_lines : 2; // Can be 0, 1 or 2
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

#ifndef NFA_H_
#define NFA_H_

#define MIN(a,b) (((a)<(b))?(a):(b))
#define LIST_IN_ARRAY 8

/*
	Description: Add a self-loop labeled with ".". Reads
	everything but the \n character.
	Arguments:
		- st, state with the self-loop.
	Return: Nothing.
*/
void add_self_loop(int st);

/*
	Description: Add a new edge to the automaton. Lazy addition.
	Actually, it modifies variable trule, rather than accessing to
	automaton[rule].
	Arguments:
		- i, origin state of the edge.
		- f, end state of the edge.
	Return: Nothing.
*/
void add_edge(short i, short f);

/*
	Description: Add a new edge to the automaton, accessing to it directly.
	Arguments:
		- i, origin state of the edge.
		- f, end state of the edge.
	Return: Nothing.
*/
void add_edge_direct(short i, short f);

// Cannot use macro memory_get within another macro
/*
	Description: Iterates over the list of edges labeled
	by right.
	Arguments:
		- None
	Return: Nothing.
*/
#define iterate_right(it, command1, command2) \
rpairs = (tright.pairs_used ? tright.pairs_used : NUM_PAIRS_INITIAL); \
\
for (it = 0; it < rpairs; it++) { \
	command1 \
} \
\
if (tright.first_block != -1) { \
	pright = mem.blocks[tright.first_block][tright.first_index]; \
	while (pright.final[0] != 0){ \
		for (it = 0; it < NUM_PAIRS_PER_STRUCT; it++) { \
			if (pright.final[it] == 0) break; \
			command2 \
		} \
		if (pright.next_block == -1) break; \
		pright = mem.blocks[pright.next_block][pright.next_index]; \
	} \
} \

/*
	Description: Iterates over the list of edges labeled
	by left.
	Arguments:
		- None
	Return: Nothing.
*/
#define iterate_left(it, command1, command2) \
lpairs = (tleft.pairs_used ? tleft.pairs_used : NUM_PAIRS_INITIAL);\
\
for (it = 0; it < lpairs; it++) {\
	command1 \
}\
\
if (tleft.first_block != -1) {\
	pleft = mem.blocks[tleft.first_block][tleft.first_index];\
	while (pleft.final[0] != 0){\
		for (it = 0; it < NUM_PAIRS_PER_STRUCT; it++) {\
			if (pleft.final[it] == 0) break; \
			command2 \
		}\
		if (pleft.next_block == -1) break;\
		pleft = mem.blocks[pleft.next_block][pleft.next_index];\
	}\
}\

/*
	Description: Performs saturation construction over rule
	rule → left right.
	Updates the counting information by invoking "count" module
	when needed.

	Arguments:
		- None
	Return: Nothing.
*/
void add_rule();

/*
	Description: Updates the state of the search for a sequence
	of symbols based on the next symbol.

	Sequence: ... Xi Xj Xk ....
	rule: variable generating X1 ... Xk, to be processed.
	left: variable generating X1 ... Xj, already processed.
	right: variable generating Xk, already processed.

	Arguments:
		- None
	Return: Nothing.
*/
void add_rule_seq();
void add_rule_seq_count();

/*
	Description: Free memory allocated by the automaton.
	Arguments:
		- None.
	Return: Nothing.
*/
void free_automaton();

#endif
