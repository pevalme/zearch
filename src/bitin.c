/*
	Description: Implementation of a bitarray reading from file.

	Properties:
		- Extracted from an implementation of Shirou Maruyama (2011)
		- Original used on Re-Pair

	Author: Pedro Valero
	Date: 12-17
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