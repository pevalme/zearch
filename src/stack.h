/*
	Description: Implementation of a stack.

	Properties:
		- Each element is a long.
		- Stack implemented as an array.
		- Array re-allocated upon need.

	Author: Pedro Valero
	Date: 12-17

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

#ifndef STACK_H_
#define STACK_H_

#define STACK_SIZE 100

typedef struct{
	int top;
	int size;
	long *data;
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
long stack_pop(STACK *s);

/*
	Description: Adds an element to the top of the
	STACK.

	Arguments:
		- *s, pointer to a STACK.
		- n, value to add.
	Return: Nothing.
*/
void stack_push(STACK *s, long n);

/*
	Description: Free memory allocated by the STACK.

	Arguments:
		- *s, pointer to a STACK.
	Return: Nothing.
*/
void stack_free(STACK *s);

#endif