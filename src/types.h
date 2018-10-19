#ifndef TYPES_H_
#define TYPES_H_

#define ALPHABET_SIZE 256
#define MATCH_MAX_LENGTH 1000
#define MAX_REGEX_SIZE 1024
#define SMALL_REGEX_BOUND 256
#define NUM_PAIRS_INITIAL 4
#define NUM_PAIRS_PER_STRUCT 2
#define BITS_PAIRS_USED 2
#define COUNTER_TOP 16777216
#define OP 1

typedef struct {
	short next_block;
	short next_index;
	short initial[NUM_PAIRS_PER_STRUCT];
	short final[NUM_PAIRS_PER_STRUCT];
} PAIR;

typedef struct {
	unsigned int left_symbol;
	unsigned int right_symbol;
} GRAMMAR_RULE;

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

typedef struct {
	unsigned char new_lines : 2; // Can be 0, 1 or 2
	// Variables for counting
	unsigned char match : 1;
	unsigned char right : 1;
	unsigned char left : 1;
} TRANSITION_SEQ;

#ifdef STATS
typedef struct {
	double value;
	double sample;
} AVERAGE;
#endif

#ifdef DEBUG
 #define DEBUG_PRINT(...) do{fprintf(stderr, __VA_ARGS__);} while(0)
#else
 #define DEBUG_PRINT(...) /* Don't do anything in release builds */
#endif

#endif