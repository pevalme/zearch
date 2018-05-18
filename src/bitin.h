/*
	Description: Implementation of a bitarray reading from file.

	Properties:
		- Extracted from an implementation of Shirou Maruyama (2011)
		- Original used on Re-Pair

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

#ifndef BITIN_H_
#define BITIN_H_


#define BITIN_BUF_LEN 131072 /* BITIN_BUF_LEN*sizeof(unsigned int) bytes */
#define W_BITS 32
#define BYTE_SIZE 256
#define BITS_PER_BYTE 8
#define CHAR_SIZE 256

typedef struct bit_input {
  FILE *input;
  unsigned int bitlen;
  unsigned int bitbuf;
  unsigned int *bufpos;
  unsigned int *buftop;
  unsigned int *bufend;
} BITIN;


/*
	Description: Initializes BITIN from which a certain amount of bits can be read from a file.
	Arguments:
		- File to read from.
	Return: Initialized BITIN.
*/
BITIN *createBitin(FILE *input);

/*
	Description: Read rblen (up to 32) bits from BITIN.
	Arguments:
		- *b, BITIN to read from.
		- rblen, amount of bits to be read.
	Return: Integer with read bits.
*/
unsigned int readBits(BITIN *b, unsigned int rblen);

#endif