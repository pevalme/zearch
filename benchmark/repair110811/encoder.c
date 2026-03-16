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

#include "encoder.h"

uint bits (uint n)
{ uint b = 0;
  while (n)
    { b++; n >>= 1; }
  return b;
}

void putLeaf(uint numcode, uint lvcode, BITOUT *bitout) {
  uint bitslen = bits(numcode);
  writeBits(bitout, lvcode, bitslen);
}

void putParen(uchar b, BITOUT *bitout) {
  if (b == OP) {
    writeBits(bitout, OP, 1);
  }
  else {
    writeBits(bitout, CP, 1);
  }
}

void encodeCFG_rec(uint code, EDICT *dict, BITOUT *bitout) {
  static uint newcode = CHAR_SIZE;

  if (dict->tcode[code] == DUMMY_CODE) {
    encodeCFG_rec(dict->rule[code].left, dict, bitout);
    encodeCFG_rec(dict->rule[code].right, dict, bitout);
    dict->tcode[code] = ++newcode;
    putParen(CP, bitout);
  }
  else {
    putParen(OP, bitout);
    if (code < CHAR_SIZE) {
      putLeaf(newcode, code, bitout);
    }
    else {
      putLeaf(newcode, dict->tcode[code], bitout);
    }
  }
}

void EncodeCFG(EDICT *dict, FILE *output) {
  uint i;
  BITOUT *bitout;

  printf("Encoding CFG...");
  fflush(stdout);
  fwrite(&(dict->txt_len), sizeof(uint), 1, output);
  fwrite(&(dict->num_rules), sizeof(uint), 1, output);
  fwrite(&(dict->seq_len), sizeof(uint), 1, output);

  bitout = createBitout(output);
  for (i = 0; i < dict->seq_len; i++) {
    encodeCFG_rec(dict->comp_seq[i], dict, bitout);
    putParen(CP, bitout);
  }
  flushBitout(bitout);
  printf("Finished!\n");
}

EDICT *ReadCFG(FILE *input) {
  uint i;
  uint num_rules, seq_len, txt_len;
  EDICT *dict;
  RULE *rule;
  CODE *comp_seq;
  CODE *tcode;

  fread(&txt_len, sizeof(uint), 1, input);
  fread(&num_rules, sizeof(uint), 1, input);
  fread(&seq_len, sizeof(uint), 1, input);
  printf("txt_len = %d\n", txt_len);
  printf("num_rules = %d\n", num_rules);
  printf("seq_len = %d\n", seq_len);

  rule = (RULE*)malloc(sizeof(RULE)*(num_rules));
  for (i = 0; i <= CHAR_SIZE; i++) {
    rule[i].left = (CODE)i;
    rule[i].right = DUMMY_CODE;
  }
  fread(rule+CHAR_SIZE+1, sizeof(RULE), num_rules-(CHAR_SIZE+1), input);

  comp_seq = (CODE*)malloc(sizeof(CODE)*seq_len);
  fread(comp_seq, sizeof(CODE), seq_len, input);

  tcode = (CODE*)malloc(sizeof(CODE)*num_rules);
  for (i = 0; i <= CHAR_SIZE; i++) {
    tcode[i] = i;
  }
  for (i = CHAR_SIZE+1; i < num_rules; i++) {
    tcode[i] = DUMMY_CODE;
  }

  dict = (EDICT*)malloc(sizeof(EDICT));
  dict->txt_len = txt_len;
  dict->num_rules = num_rules;
  dict->rule = rule;
  dict->seq_len = seq_len;
  dict->comp_seq = comp_seq;
  dict->tcode = tcode;
  return dict;
}

void DestructEDict(EDICT *dict)
{
  free(dict->rule);
  free(dict->comp_seq);
  free(dict->tcode);
  free(dict);
}

