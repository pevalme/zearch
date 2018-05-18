/*
	Description: Operations required to use SIMD.

	Example:
	Consider rule X → AB with the following pair of states connected by each variable:
		A: {(1,2),(3,4),(5,6)}
		B: {(1,3),(6,9),(2,11)}
	After compiling we have
		SIMD_A: origin = [1,3,4,-1,-1,-1,-1,-1], destiny = [2,4,6,?,?,?,?,?], destiny = 5192534549066999519616422834601983L
		SIMD_B: origin = [1,6,9,-1,-1,-1,-1,-1], destiny = [3,9,11,?,?,?,?,?], destiny = 5192772239599171410702349339983871L
	To search for coincidences of A_destiny and B_origin we apply the following algorithm
		For j in 1..3
			n = A_destiny[j]
			Compile [n,n,n,0,0,0,0,0] → x
			SIMD_compare x, 5192772239599171410702349339983871 → aux
			For i in aux
				if i \neq 0
					Found concatenation A_origin[j] → B_origin[i] → B_destiny[i]

	Properties:
		- There is no transition ending on the initial state (by definition of the extended saturation construction this case assumption is completely safe.)
		- Meant to perform the operations related to the saturation construction, i.e., joint of binary relation.
		- Each element is a 16-bits value and represents the original/final state of a transition.
		- Notation: Assume we are processing 'A' in rule 'X → AB'

	Author: Pedro Valero
	Date: 01-18

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

#ifndef SIMD_H_
#define SIMD_H_

#define VEC_SIZE 8
#define NUM_SIMD_BLOCKS_INITIAL 1

#include "emmintrin.h" // SSE2

typedef struct {
	unsigned short destiny[VEC_SIZE]; // List of origins of transitions labeled with B
	__m128i reg_origin; // 128-bits register containing the description of 8 16-bits origin states.
	unsigned char top; // Last transition in the last block
} SIMD_BLOCK;

typedef struct {
	SIMD_BLOCK *transitions; // List of blocks
	unsigned char last; // Last block in the list
	unsigned char num; // Number of elements in the list
} SIMD_SYMBOL;


/*
	Description: Initializes a SIMD_SYMBOL, allocating
	memory for NUM_SIMD_BLOCKS_INITIAL blocks.

	Arguments:
		- s, pointer to SIMD_SYMBOL to be initialized
	Return: Nothing.
*/
void simd_init(SIMD_SYMBOL *s);

/*
	Description: Stores a transitions in the SIMD data structure.
	This function is used to create a copy of a list of transitions
	labeled with a given symbol and assumes the list contained no
	duplicates.

	Arguments:
		- s, pointer to SIMD_SYMBOL to be initialized
		- i, state from which transition leaves
		- f, state to which transition arrives
	Return: Nothing.
*/
void simd_add(SIMD_SYMBOL *s, short i, short f);

void simd_add_2(SIMD_SYMBOL *s, short i, short f1, short f2);

/*
	Description: Loads information about the origin
	transitions into a 128-bit register.

	Arguments:
		- s, pointer to SIMD_SYMBOL to be compiled
	Return: Nothing.
*/
void simd_compile(SIMD_SYMBOL *s);

/*
	Description: Looks for a 16-bits number in a list using SIMD.
	It operates in linear time.

	Arguments:
		- l, number we are looking for
		- r, representation of the list using 128-bits (8 numbers)
		- n, number of values contained in the list, the rest are garbage
		- ret, pointer to a list of 16-bits numbers in which the result
		of each comparison will be stored
	Return: Nothing.
*/
void simd_find_in_vector(short l, __m128i r, int n, short *ret);

/*
	Description: Main function of the class. Applies the saturation construction.

	Arguments:
		- l, left symbol on the right-hand size of the rule
		- r, right symbol on the right-hand size of the rule
	Return: 0 if no transition labeled with X connects the initial and final state, 1 if it does and 2 if, besides, there is a non-initial-nor-final state q' such that there exists transitions (q0,A,q')(q',B,qf).
*/
int simd_join(SIMD_SYMBOL *l, SIMD_SYMBOL *r);

/*
	Description: Reset the SIMD_SYMBOL to be used again.

	Arguments:
		- s, SIMD_SYMBOL to be reseted.
	Return: Nothing.
*/
void simd_reset(SIMD_SYMBOL *s);

/*
	Description: Free memory allocated by the SIMD_SYMBOL.

	Arguments:
		- s, SIMD_SYMBOL to be freed.
	Return: Nothing.
*/
void simd_free(SIMD_SYMBOL *s);

#endif