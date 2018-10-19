/*
	Description: Implementation of a stack.

	Properties:
		- Each element is a uint.
		- Stack implemented as an array.
		- Array re-allocated upon need.

	Author: Pedro Valero
	Date: 12-17
*/

#ifndef STACK_H_
#define STACK_H_

#define STACK_SIZE 1048576

typedef struct{
	int top;
	int size;
	uint *data;
} STACK;

/*
	Description: Initializes the array "data" with
	size "STACK_SIZE".
	Arguments:
		- *s, pointer to a STACK.
	Return: Nothing
*/
void stack_init(STACK *s);

/*
	Description: Extracts an element from the top
	of the STACK.
	Arguments:
		- *s, pointer to a STACK.
	Return: Extracted element.
*/
uint stack_pop(STACK *s);

/*
	Description: Adds an element to the top of the
	STACK.
	Arguments:
		- *s, pointer to a STACK.
		- n, value to add.
	Return: Nothing.
*/
void stack_push(STACK *s, uint n);

/*
	Description: Free memory allocated by the STACK.
	Arguments:
		- *s, pointer to a STACK.
	Return: Nothing.
*/
void stack_free(STACK *s);

#endif