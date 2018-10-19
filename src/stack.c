/*
	Description: Implementation of a stack.

	Properties:
		* Each element is a long.
		* Stack implemented as an array.
		* Array re-allocated upon need.

	Author: Pedro Valero
	Date: 12-17
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