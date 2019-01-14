/*
	Description: Implementation of a stack.

	Properties:
		* Each element is a long.
		* Stack implemented as an array.
		* Array re-allocated upon need.

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
#include "stack.h"
#include "types.h"

void stack_init(STACK *s){
	posix_memalign((void **)&s->data, 64, STACK_SIZE * sizeof(uint));
	s->top = -1;
	s->size = STACK_SIZE;
}

__attribute__((always_inline)) inline uint stack_pop(STACK *s){
	uint ret;

	if (s->top == -1) {
		printf("EMPTY STACK\n");
		exit(-1);
	}
	ret = s->data[s->top--];
	return ret;
}

__attribute__((always_inline)) inline void stack_push(STACK *s, uint n){
	if (s->top == s->size - 1) {
		s->size = s->size + STACK_SIZE;
		s->data = (uint*)realloc(s->data, sizeof(uint) * s->size);
	}

	s->data[++s->top] = n;
}

void stack_free(STACK *s){
	free(s->data);
}