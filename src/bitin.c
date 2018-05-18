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

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include "bitin.h"
#include "types.h"

BITIN *createBitin(FILE *input) {
	BITIN *b = (BITIN*)malloc(sizeof(BITIN));

	b->input = input;
	b->bitlen = 0;
	b->bitbuf = 0;
	b->buftop = (unsigned int*)calloc(BITIN_BUF_LEN, sizeof(unsigned int));
	b->bufpos = b->bufend = b->buftop;

  return b;
}

unsigned int readBits(BITIN *b, unsigned int rblen) {
  unsigned int x;
  unsigned int s, n;

  if (rblen < b->bitlen) {
	x = b->bitbuf >> (W_BITS - rblen);
	b->bitbuf <<= rblen;
	b->bitlen -= rblen;
  }
  else {
	if (b->bufpos == b->bufend) {
	  n = fread(b->buftop, sizeof(unsigned int), BITIN_BUF_LEN, b->input);
	  b->bufpos = b->buftop;
	  b->bufend = b->buftop + n;
	  if (b->bufend < b->buftop) {
		fprintf(stderr, "Error: new bits buffer was not loaded.\n");
		exit(1);
	  }
	}

	s = rblen - b->bitlen;
	x = b->bitbuf >> (W_BITS - b->bitlen - s);
	b->bitbuf = *(b->bufpos);
	b->bufpos++;
	b->bitlen = W_BITS - s;
	if (s != 0) {
	  x |= b->bitbuf >> b->bitlen;
	  b->bitbuf <<= s;
	}
  }

  return x;
}