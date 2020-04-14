/*
	Description: Program to check the emptiness of the intersection of an SLP and an NFA.

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
#include <fa.h>

#include "types.h"
#include "stack.h"
#include "memory.h"
#include "count.h"
#include "bitin.h"
#include "nfa.h"

/*
	Overflow trick works for, at most, one overflow.
*/

/*****************************

	  GLOBAL VARIABLES

* Max 32K states for automaton
* Max 2**32 symbols which ensures at least
	1GB of uncompressed text can be handled.

*****************************/
GRAMMAR_RULE *grammar = NULL;
TRANSITION_FULL *automaton = NULL;
TRANSITION_SEQ *automaton_seq = NULL;
int recently_added[MAX_REGEX_SIZE][MAX_REGEX_SIZE] __attribute__ ((aligned)) = {{0}};
int reached_states[MAX_REGEX_SIZE] __attribute__ ((aligned)) = {0};
int reached_states2[MAX_REGEX_SIZE] __attribute__ ((aligned)) = {0};
short list_dots[MAX_REGEX_SIZE] __attribute__ ((aligned)) = {0};
short dots[MAX_REGEX_SIZE] __attribute__ ((aligned)) = {0};
short final_states[MAX_REGEX_SIZE] __attribute__ ((aligned)) = {0};
short num_edges[MAX_REGEX_SIZE] __attribute__ ((aligned));
short edges[MAX_REGEX_SIZE][MAX_REGEX_SIZE] __attribute__ ((aligned)) = {{0}}; // edges[q] is the list of states reachable from q
int *rs = NULL;
int *rs2 = NULL;
MEMORY mem; // Keeps track of allocated memory
unsigned int counting_overflows = 0; // Number of times the counter has suffered an overflow.
unsigned int num_rules, record_num_rules;
int seq_counter = 0;
int seq_counter_new = 0;
int index_prealloc = MAX_PREALLOCATED - 1; // Next PAIR to be used
int final_state = 0; // Final state, guessed while translating the automaton
int num_dots = 0; // Number of dot states
int rule, left, right; // Rule under study
TRANSITION_FULL tleft, tright, trule; // Automaton elements related to rules under study
TRANSITION_SEQ tsleft, tsright, tsrule; // Automaton elements related to rules under study
TRANSITION_FULL tempty = {0};
TRANSITION_SEQ tsempty = {0};
int axiom; // Identifier of the axiom
int num_states = 0; // Number of states of the NFA
char mode; // Option chose
bool expand;


#ifdef STATS
	long total_num_edges = 0;
	long used_pointers = 0;
	long bad_luck_counter = 0;
	long skipped = 0;
	long pskipped = 0;
	long no_connection_counter = 0;
	long qsskipped = 0;
	long wasted_memory = 0;
	long reinserted = 0;
	long num_operations_gr = 0;
	long num_operations_seq = 0;
	long num_operations_seq_old;
	long num_operations_gr_old = 0;

	uint num_e_l;
	uint num_e_r;

	AVERAGE avg;
#endif

#ifdef PLOT
	int total_num_edges;
#endif

/*****************************

		EXPANDING MATCH

*****************************/
char buffer[MATCH_MAX_LENGTH];
int bufpos = 0;

void expand_match(long leaf,  bool l,  bool r) {
	bool new_match;
	if (leaf < ALPHABET_SIZE) {
		if (l || r) {
			if (bufpos == MATCH_MAX_LENGTH-1){
				buffer[bufpos] = '\0';
				printf("%s",buffer);
				bufpos = 0;
				if (leaf == '\n' && buffer[MATCH_MAX_LENGTH-2] != '\n') buffer[bufpos++] = leaf;
			}
			if (leaf == '\n') {
				if (bufpos > 0) {
					if (buffer[bufpos-1] != '\n') buffer[bufpos++] = leaf;
				} 
			} else buffer[bufpos++] = leaf;
		}
		return;
	} else {
		// Expanding rule X → Y Z

		// "Base case"
		if (automaton[leaf].new_lines == 0) {
			if (l || r) {
				expand_match(grammar[leaf].left_symbol,l,r);
				expand_match(grammar[leaf].right_symbol,l,r);
			}
			return;
		}

		// Checking if X generates a new match
		if ((automaton[grammar[leaf].left_symbol].count + automaton[grammar[leaf].right_symbol].count) == automaton[leaf].count) {
			// No new match
			if (r) {
				if (automaton[grammar[leaf].right_symbol].new_lines == 0) {
					expand_match(grammar[leaf].left_symbol,l,true);
				} else {
					expand_match(grammar[leaf].left_symbol,l,false);
				}		
			} else {
				expand_match(grammar[leaf].left_symbol,l,false);
			}
			if (l) {
				if (automaton[grammar[leaf].left_symbol].new_lines == 0) {
					expand_match(grammar[leaf].right_symbol,true,r);
				} else {
					expand_match(grammar[leaf].right_symbol,false,r);
				}
			} else {
				expand_match(grammar[leaf].right_symbol,false,r);
			}		
		} else {
			// New match
			expand_match(grammar[leaf].left_symbol,l,true);
			expand_match(grammar[leaf].right_symbol,true,r);
		}

		return;
	}
}

void expandLeaf_right(long leaf) {
	if (leaf < ALPHABET_SIZE) {
		if (bufpos == MATCH_MAX_LENGTH-1){
			buffer[bufpos] = '\0';
			printf("%s",buffer);
			bufpos = 0;
			if (leaf == '\n' && buffer[MATCH_MAX_LENGTH-2] != '\n') buffer[bufpos++] = leaf;
		}

		if (leaf == '\n') {
			if (bufpos > 0) {
				if (buffer[bufpos-1] != '\n') buffer[bufpos++] = leaf;
			}
		} else buffer[bufpos++] = leaf;
		return;
	} else {
		if (grammar[leaf].right_symbol >= num_rules) {
			if (automaton_seq[grammar[leaf].right_symbol-num_rules].new_lines == 0) {
				expandLeaf_right(grammar[leaf].left_symbol);
				expandLeaf_right(grammar[leaf].right_symbol);
			} else expandLeaf_right(grammar[leaf].right_symbol);
		} else {
			if (automaton[grammar[leaf].right_symbol].new_lines == 0) {
				expandLeaf_right(grammar[leaf].left_symbol);
				expandLeaf_right(grammar[leaf].right_symbol);
			} else expandLeaf_right(grammar[leaf].right_symbol);
		}

		return;
	}
}

void expandLeaf_left(long leaf) {
	if (leaf < ALPHABET_SIZE) {
		if (bufpos == MATCH_MAX_LENGTH-1){
			buffer[bufpos] = '\0';
			printf("%s",buffer);
			bufpos = 0;
			if (leaf == '\n' && buffer[MATCH_MAX_LENGTH-2] != '\n') buffer[bufpos++] = leaf;
		}
		if (leaf == '\n') {
			if (bufpos > 0) {
				if (buffer[bufpos-1] != '\n') buffer[bufpos++] = leaf;
			}
		} else buffer[bufpos++] = leaf;
		return;
	} else {
		if (grammar[leaf].left_symbol >= num_rules) {
			if (automaton_seq[grammar[leaf].left_symbol-num_rules].new_lines == 0) {
				expandLeaf_left(grammar[leaf].left_symbol);
				expandLeaf_left(grammar[leaf].right_symbol);
			} else expandLeaf_left(grammar[leaf].left_symbol);
		} else {
			if (automaton[grammar[leaf].left_symbol].new_lines == 0) {
				expandLeaf_left(grammar[leaf].left_symbol);
				expandLeaf_left(grammar[leaf].right_symbol);
			} else expandLeaf_left(grammar[leaf].left_symbol);
		}

		return;
	}
}

int has_meaniningfull_trans(struct state *st) {
	struct state *st2;
	int i, nt;
	unsigned char begin, end;

	nt = fa_state_num_trans(st);
	if (nt == 0) return false;

	for (i = 0; i < nt; i++) {
		fa_state_trans(st, i, &st2, &begin, &end);
		if (st2 != st) return true;
	}

	return false;
}

void initialize_automaton(bool minimize, char *regex) {
	struct state * hashes[MAX_REGEX_SIZE] = {0};
	struct fa* fa_result = NULL;
	struct state *st, *st2;
	uint32_t num_trans, i, k, from, to;
	unsigned char begin, end;

	fa_compile(regex, strlen(regex), &fa_result);
	if (minimize) fa_minimize(fa_result);

	DEBUG_PRINT("######### Importing automaton #########\n");

	st = fa_state_initial(fa_result);
	if (st != NULL) num_states = 0;
	else {
		printf("Some error occur when building the automaton.\n");
		exit(-1);
	}
	num_states = 0;

	dots[0] = 1;

	while(st != NULL) {
		hashes[num_states++] = st;
		if (fa_state_is_accepting(st)) {
			dots[num_states-1] = 1;
			final_states[num_states-1] = 1;
		}
#ifdef DEBUG
		if (final_states[num_states-1]) DEBUG_PRINT("## Final state %d\n",num_states-1);
#endif
		st = fa_state_next(st);
	}

	st = fa_state_initial(fa_result);
	from = 0;

	while (st != NULL) {
		num_trans = fa_state_num_trans(st);

		for (i = 0; i < num_trans; i++) {
			if (-1 == fa_state_trans(st, i, &st2, &begin, &end)) {
				printf("Some error occur when building the automaton.\n");
			}

			// Detect wildcards
			if (st2 == st && begin == 0 && end == 9) {
				fa_state_trans(st, i + 1, &st2, &begin, &end);
				if (st2 == st && begin == 11 && end == 255) {
					add_self_loop(from);
					DEBUG_PRINT("## ⋅: %d %d\n",from, from);
					i++;
				} else {
					for (rule = 0; rule <= 9; rule++) {
						add_edge_direct(from, from);
						DEBUG_PRINT("## %d: %d %d\n",rule, from, from);
					}
					for (rule = begin; rule <= end; rule++) {
						add_edge_direct(from, from);
						DEBUG_PRINT("## %d: %d %d\n",rule, from, from);
					}
				}
			} else {
				// Find state to which we are pointing to.
				for (to = 0; to < num_states; to++)
					if (hashes[to] == st2) break;

				for (rule = begin; rule <= end; rule++) {
					add_edge_direct(from, to);
					DEBUG_PRINT("## %d: %d %d\n",rule, from, to);
					if (from == 0 && fa_state_is_accepting(st2)) incr_count_l1(rule);
				}
			}
		}
		st = fa_state_next(st);
		from++;
	}

	fa_free(fa_result);
	return;
}

int allocate_data_structures(int seq_len, int minimize, char *regex_str) {
	int i;

	axiom = num_rules + seq_len - 2;

	posix_memalign((void **)&automaton, 64, num_rules * sizeof(TRANSITION_FULL));
	if (automaton == NULL){
		printf("Too much memory\n");
		return -1;
	}
	memset(automaton, 0x0, num_rules * sizeof(TRANSITION_FULL));
	automaton[10].new_lines = 1;
	automaton[13].new_lines = 1;

	if (mode != 'c' && mode != 'b') {
		posix_memalign((void **)&automaton_seq, 64, seq_len * sizeof(TRANSITION_SEQ));
		if (automaton_seq == NULL){
			printf("Too much memory\n");
			return -2;
		}
		memset(automaton_seq, 0, seq_len * sizeof(TRANSITION_SEQ));

		posix_memalign((void **)&grammar, 64, (num_rules + seq_len) * sizeof(GRAMMAR_RULE));
		if (grammar == NULL){
			printf("Too much memory\n");
			return -3;
		}
	}

	memory_init();

#ifdef STATS
	avg.value = 0;
	avg.sample = 0;
#endif

	initialize_automaton(minimize, regex_str);

	DEBUG_PRINT("Num states: %d\n", num_states);
}

void print_stats(int seq_len) {
#ifdef STATS
	printf("{\n");
	printf("\"Pairs\": {\"num\": %ld, \"unit_size\": %ld, \"total_mem\": %ld},\n",total_num_edges, sizeof(PAIR), total_num_edges*sizeof(PAIR));
	printf("\"Variables\": {\"num\": %d, \"unit_size\": %ld, \"total_mem\": %ld},\n",num_rules, sizeof(TRANSITION_FULL), num_rules*sizeof(TRANSITION_FULL));
	printf("\"Axiom\": {\"len\": %d, \"unit_size\": %ld, \"total_mem\": %ld},\n",seq_len, sizeof(TRANSITION_SEQ), seq_len*sizeof(TRANSITION_SEQ));
	printf("\"Skipped\": %ld,\n",skipped);
	printf("\"Partially_skipped\": %ld,\n",pskipped);
	printf("\"Seq_skipped\": %ld,\n",qsskipped);
	printf("\"Operations per rule\": %lf,\n",(double)num_operations_gr/num_rules);
	printf("\"Operations per seq\": %lf,\n",(double)num_operations_seq/seq_len);
	printf("\"Seq len\": %ld\n",seq_len);
	printf("\"Num states\": %d\n",num_states);
	printf("}");
#endif
}

void print_required_information() {
	int ret = 0;

	if (mode != 'c') {
		if (automaton_seq[axiom-num_rules].match != 0) {
			ret = seq_counter;
			if (automaton_seq[axiom-num_rules].left) ret++;
			if (automaton_seq[axiom-num_rules].right) ret++;
			if (automaton_seq[axiom-num_rules].new_lines == 0) ret++;
		} else ret = 0;
	} else {
		if (tsrule.match != 0) {
			ret = seq_counter;
			if (tsrule.left) ret++;
			if (tsrule.right) ret++;
			if (tsrule.new_lines == 0) ret++;
		} else ret = 0;
	}

	if (mode != 'c') {
		buffer[bufpos] = '\0';
		if (buffer[bufpos-1] == '\n') printf("%s",buffer);
		else printf("%s\n",buffer);
	}

	if (mode == 'c' || mode == 'a') printf("%d\n",ret + counting_overflows*COUNTER_TOP);
}

int run_boolean_zearch(bool minimize, char *slp_filename, char *regex_str){
	FILE *slp = NULL;
	BITIN *bitin;
	STACK s;
	unsigned int ret, txt_len, seq_len, exc, read, last_rule, rules_counter, l;
	short j, k;
	bool paren, flag, done;

	slp = fopen(slp_filename,"rb");
	bitin = createBitin(slp);

	if (fread(&txt_len, sizeof(unsigned int), 1, slp) != 1){
		printf("Error reading file %s\n", slp_filename);
		exit(-1);
	}
  	if (fread(&num_rules, sizeof(unsigned int), 1, slp) != 1){
  		printf("Error reading file %s\n", slp_filename);
  		exit(-1);
  	}
  	if (fread(&seq_len, sizeof(unsigned int), 1, slp) != 1){
  		printf("Error reading file %s\n", slp_filename);
  		exit(-1);
  	}

	DEBUG_PRINT("txt_len = %d, num_rules = %d, seq_len = %d\n\n", txt_len, num_rules, seq_len);

	allocate_data_structures(seq_len, minimize, regex_str);

	stack_init(&s);

	// Extracting grammars from compressed file
	rules_counter = CHAR_SIZE;
	last_rule = num_rules;

	flag = 1;
	for (l = 0; l < seq_len; l++) {
		exc = 0;
		done = 0;
		while (1) {
			paren = readBits(bitin, 1);
			if (paren == OP) {
				exc++;
				read = readBits(bitin, 32-__builtin_clz(rules_counter));
				stack_push(&s,read);
			} else {
				exc--;
				if (exc == 0 && flag){
					flag = 0;
					break;
				}

				right = stack_pop(&s);
				left = stack_pop(&s);

				if (exc == 0) {
					rule = last_rule++;
					done = 1;
					stack_push(&s,rule);
					add_rule_seq_count();
					if (tsrule.match || tsrule.left || tsrule.right) {
						printf("MATCH\n");
						goto FREE_AND_EXIT;
					}
				} else {
					rule = ++rules_counter;
					stack_push(&s,rule);
					add_rule();
					automaton[rule] = trule;
					if (trule.count) {
						printf("MATCH\n");
						goto FREE_AND_EXIT;
					}
				}

				if (done) break;
			}
		}
	}

	printf("DOES NOT MATCH\n");

FREE_AND_EXIT:
	stack_free(&s);

#if STATS
	print_stats(seq_len);
#endif

	free(bitin->buftop);
	free(bitin);
	fclose(slp);
	return ret;
}

int run_zearch(bool minimize, char *slp_filename, char *regex_str){
	FILE *slp = NULL;
	BITIN *bitin;
	STACK s;
	unsigned int ret, txt_len, seq_len, exc, read, last_rule, rules_counter, l, aux;
	int m;
	short j, k;
	bool paren, flag, done, first_line;

	slp = fopen(slp_filename,"rb");
	bitin = createBitin(slp);

	if (fread(&txt_len, sizeof(unsigned int), 1, slp) != 1){
		printf("Error reading file %s\n", slp_filename);
		exit(-1);
	}
  	if (fread(&num_rules, sizeof(unsigned int), 1, slp) != 1){
  		printf("Error reading file %s\n", slp_filename);
  		exit(-1);
  	}
  	if (fread(&seq_len, sizeof(unsigned int), 1, slp) != 1){
  		printf("Error reading file %s\n", slp_filename);
  		exit(-1);
  	}

	DEBUG_PRINT("txt_len = %d, num_rules = %d, seq_len = %d\n\n", txt_len, num_rules, seq_len);

	// TODO: Proper error control required for this function
	allocate_data_structures(seq_len, minimize, regex_str);

#ifdef PLOT
	total_num_edges = 0;
#endif

	stack_init(&s);

	// Extracting grammar from compressed file
	rules_counter = CHAR_SIZE;
	last_rule = num_rules;

	flag = 1;
	first_line = true;
	if (mode != 'c') {
		for (l = seq_len; l !=0; --l) {
			exc = 0;
			done = 0;
			while (1) {
				paren = readBits(bitin, 1);
				if (paren == OP) {
					exc++;
					rule = readBits(bitin, 32-__builtin_clz(rules_counter));
					stack_push(&s,rule);
				} else {
					exc--;
					if (exc == 0 && flag){
						if (automaton[rule].left) {
							expandLeaf_left(rule);
							first_line = false;
						}
						expand_match(rule,false,false);
						if (automaton[rule].new_lines) first_line = false;
						flag = 0;
						break;
					}

					right = stack_pop(&s);
					left = stack_pop(&s);

					expand = 0;

					if (exc == 0) {
						rule = last_rule++;
						done = 1;
						stack_push(&s,rule);
						add_rule_seq();
						automaton_seq[rule-num_rules] = tsrule;
						grammar[rule].left_symbol=left;
						grammar[rule].right_symbol=right;
						if (first_line) {
							if (left >= num_rules) {
								if (automaton_seq[left-num_rules].left) {
									expandLeaf_left(left);
								} else if (automaton_seq[left-num_rules].new_lines) first_line = false;
							} else {
								if (automaton[left].left) {
									expandLeaf_left(left);
									first_line = false;
								} else if (automaton[left].new_lines) first_line = false;
							}
						}
						if (expand) {
							expandLeaf_right(left);
							expandLeaf_left(right);
						}
						expand_match(right,false,false);
						break;
					} else {
						rule = ++rules_counter;
						stack_push(&s,rule);
						add_rule();
						if (__builtin_expect((COUNTER_TOP - automaton[left].count) <= automaton[right].count,0)) counting_overflows++;
						automaton[rule] = trule;
#ifdef PLOT
						printf("%d,%d,%d\n",left, right, total_num_edges);
						total_num_edges = 0;
#endif
						grammar[rule].left_symbol=left;
						grammar[rule].right_symbol=right;
					}
				}
			}
		}
	} else {
		for (l = seq_len; l !=0; --l) {
			exc = 0;
			done = 0;
			while (1) {
				paren = readBits(bitin, 1);
				if (paren == OP) {
					exc++;
					rule = readBits(bitin, 32-__builtin_clz(rules_counter));
					stack_push(&s,rule);
				} else {
					exc--;
					if (exc == 0 && flag){
						flag = 0;
						break;
					}

					right = stack_pop(&s);
					left = stack_pop(&s);

					expand = 0;

					if (exc == 0) {
						rule = last_rule++;
						done = 1;
						stack_push(&s,rule);
#ifdef STATS						
						num_operations_seq_old = num_operations_seq;
#endif
						add_rule_seq_count();
#ifdef STATS 
						printf("STATS s: %ld\n",(num_operations_seq - num_operations_seq_old));
#endif	
						break;
					} else {
						rule = ++rules_counter;
						stack_push(&s,rule);
#ifdef STATS
						num_operations_gr_old = num_operations_gr;
#endif						
						add_rule();
#ifdef STATS
						printf("STATS sxs: %ld\n",(num_operations_gr-num_operations_gr_old));
#endif												
						if (__builtin_expect((COUNTER_TOP - automaton[left].count) <= automaton[right].count,0)) counting_overflows++;
						automaton[rule] = trule;							
#ifdef PLOT
						printf("%d,%d,%d\n",left, right, total_num_edges);
						total_num_edges = 0;
#endif
					}
				}
			}
		}
	}

#if !defined(STATS) && !defined(PLOT)
	print_required_information();
#endif
	stack_free(&s);

#if STATS
	print_stats(seq_len);
#endif

	memory_free();
	free(automaton);
	if (mode != 'c') free(automaton_seq);
	if (mode != 'c') free(grammar);

	free(bitin->buftop);
	free(bitin);
	fclose(slp);
	return ret;
}

int main(int argc, char** argv){
	int ret, minimize = false, improved = false, op;

	if (argc <= 3 || argc >= 7){
		printf("Wrong arguments.\n");
		printf("Usage: ./program <operation> <regex> <input_grammar>\n");
		printf("\t Grammar format: Compact representation used by Re-Pair\n");
		// printf("\t When -m is used the automaton will be minimized. Note that this might have a negative impact on performance\n");
		printf("\nValues for <operation>:\n");
		printf("\t -c: prints only the total number of lines matching the pattern\n");
		printf("\t -l: prints only the matching lines as they occur in the uncompressed file\n");
		printf("\t -a: c+l\n");
		printf("\t -b: prints a boolean indicating whether there is, at least, a match or not\n");
		exit(0);
	}

	if (argc >= 4) {
		if (argv[argc-3][0] == '-') {
			mode = argv[argc-3][1];
		}
		for (op = 1; op <= argc-4; op++) {
			if (argv[op][0] == '-' && argv[op][1] == 'm') minimize = true;
			else printf("Invalid argument. No minimization will be performed\n");
		}
	}

	if (mode != 'a' && mode != 'c' && mode != 'l' && mode != 'b') {
		printf("Invalid option. Option -c executed by default\n");
		mode = 'c';
	}

	DEBUG_PRINT("\n\nMeaning of debug output:\n");

	DEBUG_PRINT("Looking at: R (cr) → A (ca) B (cb)\n");
	DEBUG_PRINT("\tConsidering rule R → AB\n");
	DEBUG_PRINT("\tcx: Number of new lines characters generated by X. Can be 0, 1 or >=2\n\n");

	DEBUG_PRINT("Adding R (i,f)\n");
	DEBUG_PRINT("\tAdding to the automaton symbol R connecting states i → f\n\n");

	DEBUG_PRINT("[count, left, right, new_lines, match]\n");
	DEBUG_PRINT("\tcount: Number of lines matching the pattern generated by this symbol\n");
	DEBUG_PRINT("\tleft/right: There is a match on the left/right of the left/right most new line character generated by this symbol\n");
	DEBUG_PRINT("\tnew_lines: Number of new lines characters generated by this symbol. Can be 0, 1 or >=2.\n");
	DEBUG_PRINT("\tmatch: If the string generated by this symbol matches the pattern\n\n");

	if (mode == 'b') run_boolean_zearch(minimize, argv[argc-1], argv[argc-2]);
	else run_zearch(minimize, argv[argc-1], argv[argc-2]);

	exit(0);
}
