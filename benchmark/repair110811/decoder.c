/* 
 *  Copyright (c) 2011 Shirou Maruyama
 * 
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 * 
 *   1. Redistributions of source code must retain the above Copyright
 *      notice, this list of conditions and the following disclaimer.
 *
 *   2. Redistributions in binary form must reproduce the above Copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *
 *   3. Neither the name of the authors nor the names of its contributors
 *      may be used to endorse or promote products derived from this
 *      software without specific prior written permission.
 */


#include "decoder.h"

#define BUFF_SIZE 32768
char buffer[BUFF_SIZE];
uint bufpos = 0;

uint bits (uint n);
void expandLeaf(RULE *rule, CODE code, FILE *output);

uint bits (uint n)
{ uint b = 0;
  while (n)
    { b++; n >>= 1; }
  return b;
}

void expandLeaf(RULE *rule, CODE leaf, FILE *output) {
  if (leaf < CHAR_SIZE) {
    buffer[bufpos] = leaf;
    bufpos++;
    if (bufpos == BUFF_SIZE) {
      fwrite(buffer, 1, BUFF_SIZE, output);
      bufpos = 0;
    }
    return;
  }
  else {
    expandLeaf(rule, rule[leaf].left, output);
    expandLeaf(rule, rule[leaf].right, output); 
    return;
  }
}

void DecodeCFG(FILE *input, FILE *output) {
  uint i;
  RULE *rule;
  uint num_rules, txt_len, seq_len;
  BITIN *bitin;
  uint exc, sp;
  CODE *stack;
  CODE newcode, leaf;
  uint bitlen;
  bool paren;

  fread(&txt_len, sizeof(uint), 1, input);
  fread(&num_rules, sizeof(uint), 1, input);
  fread(&seq_len, sizeof(uint), 1, input);
  printf("txt_len = %d, num_rules = %d, seq_len = %d\n", 
	 txt_len, num_rules, seq_len);

  rule = (RULE*)malloc(sizeof(RULE)*num_rules);
  for (i = 0; i <= CHAR_SIZE; i++) {
    rule[i].left = (CODE)i;
    rule[i].right = DUMMY_CODE;
  }

  for (i = CHAR_SIZE+1; i < num_rules; i++) {
    rule[i].left = DUMMY_CODE;
    rule[i].right = DUMMY_CODE;
  }

  stack = (CODE*)malloc(sizeof(CODE)*num_rules);
  for (i = 0; i < num_rules; i++) {
    stack[i] = DUMMY_CODE;
  }

  printf("Decoding CFG...");
  fflush(stdout);
  bitin = createBitin(input);
  newcode = CHAR_SIZE;

  for (i = 0; i < seq_len; i++) {
    exc = 0; sp = 0;
    while (1) {
      paren = readBits(bitin, 1);
      if (paren == OP) {
	exc++;
	bitlen = bits(newcode);
	//printf("bitlen = %d\n", bitlen);
	leaf = readBits(bitin, bitlen);
	expandLeaf(rule, leaf, output);
	stack[sp++] = leaf;
      }
      else {
	exc--;
	if (exc == 0) break;
	newcode++;
	rule[newcode].right = stack[--sp];
	rule[newcode].left  = stack[--sp];
	stack[sp++] = newcode;
      }
    }
  }
  fwrite(buffer, 1, bufpos, output);
  printf("Finished!\n");
  free(rule);
}

