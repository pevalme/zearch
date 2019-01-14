/*
	Description: Operations required to use SIMD.

	Properties:
		* There is no transition ending on the initial state (by definition of the extended saturation construction this case assumption is completely safe.)
		* Meant to perform the operations related to the saturation construction, i.e., joint of binary relation.
		* Each element is a 16-bits value and represents the original/final state of a transitions.
		* Notation: Assume we are processing 'A' in rule 'X → AB'

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
#include "types.h"
#include "simd.h"
#include "nfa.h"
#include "emmintrin.h" // SSE2


void simd_init(SIMD_SYMBOL *s) {
	s->transitions = (SIMD_BLOCK*)malloc(NUM_SIMD_BLOCKS_INITIAL * sizeof(SIMD_BLOCK));
	s->last = 0;
	s->num = NUM_SIMD_BLOCKS_INITIAL;

	s->transitions[s->last].top = 0;
}

void simd_add(SIMD_SYMBOL *s, short i, short f) {
	__m128i aux1, aux2;

	if (s->transitions[s->last].top == VEC_SIZE) {
		s->last++;
		if (s->num == s->last) {
			s->transitions = (SIMD_BLOCK*) realloc(s->transitions, sizeof(SIMD_BLOCK) * ++s->num);
		}
		s->transitions[s->last].top = 0;
	}

	s->transitions[s->last].destiny[s->transitions[s->last].top] = f;

	aux1 = _mm_srli_si128(s->transitions[s->last].reg_origin,2);
	aux2 = _mm_set_epi16(i,0,0,0,0,0,0,0);
	s->transitions[s->last].reg_origin = _mm_or_si128(aux1, aux2);

	s->transitions[s->last].top++;
}

void simd_add_2(SIMD_SYMBOL *s, short i, short f1, short f2) {
	__m128i aux1, aux2;

	if (s->transitions[s->last].top == VEC_SIZE) {
		s->last++;
		if (s->num == s->last) {
			s->transitions = (SIMD_BLOCK*) realloc(s->transitions, sizeof(SIMD_BLOCK) * ++s->num);
		}
		s->transitions[s->last].top = 0;

		s->transitions[s->last].destiny[s->transitions[s->last].top] = f1;
		s->transitions[s->last].destiny[s->transitions[s->last].top+1] = f2;

		aux1 = _mm_srli_si128(s->transitions[s->last].reg_origin,4);
		aux2 = _mm_set_epi16(i,i,0,0,0,0,0,0);
		s->transitions[s->last].reg_origin = _mm_or_si128(aux1, aux2);

		s->transitions[s->last].top+=2;
	} else if (s->transitions[s->last].top == VEC_SIZE - 1) {
		simd_add(s,i,f1);
		simd_add(s,i,f2);
	} else {
		s->transitions[s->last].destiny[s->transitions[s->last].top] = f1;
		s->transitions[s->last].destiny[s->transitions[s->last].top+1] = f2;

		aux1 = _mm_srli_si128(s->transitions[s->last].reg_origin,4);
		aux2 = _mm_set_epi16(i,i,0,0,0,0,0,0);
		s->transitions[s->last].reg_origin = _mm_or_si128(aux1, aux2);

		s->transitions[s->last].top+=2;
	}
}

/*
void simd_compile(SIMD_SYMBOL *s) {
	int i;

	for (i = 0; i <= s->last; i++) {
		s->transitions[i].reg_origin = _mm_srli_si128(s->transitions[i].reg_origin,(8-s->transitions[i].top)*2);
	}
}
*/

void simd_find_in_vector(short l, __m128i r, int n, short *ret) {
	int i;
	__m128i m_left;
	__m128i res;

	DEBUG_PRINT("Looking for %d in list of size %d...\n", l, n);

	m_left = _mm_set1_epi16(l);
	res = _mm_cmpeq_epi16(m_left, r);
	_mm_store_pd((double*)ret, _mm_castsi128_pd(res));
}

/*
int simd_join(SIMD_SYMBOL *l, SIMD_SYMBOL *r) {
	int blocks_l, blocks_r;
	int i,j;
	int ret = 0;
	int count = 0;
	short aux[VEC_SIZE];
	__m128i m_left;

	DEBUG_PRINT("Joining: left=%d (%d), right=%d (%d)\n",l->last,l->transitions[l->last].top, r->last, r->transitions[r->last].top);

	for (blocks_l = 0; blocks_l <= l->last; blocks_l++) {
		for (blocks_r = 0; blocks_r <= r->last; blocks_r++) {

			for (i = 0; i < l->transitions[blocks_l].top; i++) {
				simd_find_in_vector(l->transitions[blocks_l].destiny[i], r->transitions[blocks_r].reg_origin, r->transitions[blocks_r].top, (short*)aux);
				for (j = 0; j < r->transitions[blocks_r].top; j++) {
					if (!aux[j + VEC_SIZE - r->transitions[blocks_r].top]) {
						count++;
						add_edge(l->transitions[blocks_l].origin[i],r->transitions[blocks_r].destiny[j]);
						if (ret != 2 && l->transitions[blocks_l].origin[i] == 0 && r->transitions[blocks_r].destiny[j] == final_state) {
							if (ret == 0) ret = 1;
							if (l->transitions[blocks_l].destiny[i] != 0 && l->transitions[blocks_l].destiny[i] != final_state) ret = 2;
						}
					}
				}
			}
		}
	}

	return ret;
}
*/

void simd_reset(SIMD_SYMBOL *s) {
	s->last = 0;
	s->transitions[0].top = 0;
	s->transitions[0].reg_origin = _mm_setzero_si128();
}

void simd_free(SIMD_SYMBOL *s) {
	free(s->transitions);
}