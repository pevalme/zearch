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

#ifdef REPAIR
#include "repair.h"
#include "encoder.h"
#include "string.h"

EDICT *convertDict(DICT *dict)
{
  EDICT *edict = (EDICT*)malloc(sizeof(EDICT));
  uint i;
  edict->txt_len = dict->txt_len;
  edict->seq_len = dict->seq_len;
  edict->num_rules = dict->num_rules;
  edict->comp_seq = dict->comp_seq;
  edict->rule  = dict->rule;
  edict->tcode = (CODE*)malloc(sizeof(CODE)*dict->num_rules);

  for (i = 0; i <= CHAR_SIZE; i++) {
    edict->tcode[i] = i;
  }
  for (i = CHAR_SIZE+1; i < dict->num_rules; i++) {
    edict->tcode[i] = DUMMY_CODE;
  }

  free(dict);
  return edict;
}

int main(int argc, char *argv[])
{
  char *target_filename;
  char output_filename[1024];
  FILE *input, *output;
  DICT *dict;
  EDICT *edict;

  if (argc != 2) {
    printf("Usage: %s <filename>\n"
	   "Compresses <filename> with repair and creates "
	   "<filename>.rp compressed files\n\n", argv[0]);
    exit(1);
  }
  target_filename = argv[1];
  
  input  = fopen(target_filename, "r");
  if (input == NULL) {
    puts("File open error at the beginning.");
    exit(1);
  }

  strcpy(output_filename, target_filename);
  strcat(output_filename, ".rp");
  output = fopen(output_filename, "wb");
  if (output == NULL) {
    puts("File open error at the beginning.");
    exit(1);
  }

  dict = RunRepair(input);
  edict = convertDict(dict);
  EncodeCFG(edict, output);
  DestructEDict(edict);

  fclose(input);
  fclose(output);
  exit(0);
}
#endif

#ifdef DESPAIR
#include "decoder.h"
int main(int argc, char *argv[])
{
  char input_filename[1024];
  FILE *input, *output;

  if (argc != 2) {
    printf("Usage: %s <filename>\n"
	   "Restore <filename> from <filename>.rp\n\n", argv[0]);
    exit(1);
  }
  
  strcpy(input_filename, argv[1]);
  strcat(input_filename, ".rp");

  input = fopen(input_filename, "rb");
  output = fopen(argv[1], "w");
  if (input == NULL || output == NULL) {
    printf("File open error.\n");
    exit(1);
  }
  DecodeCFG(input, output);
  fclose(input); fclose(output);
  exit(0);
}
#endif

#ifdef TXT2ENC
#include "repair.h"
#include "encoder.h"

EDICT *convertDict(DICT *dict)
{
  EDICT *edict = (EDICT*)malloc(sizeof(EDICT));
  uint i;
  edict->txt_len = dict->txt_len;
  edict->seq_len = dict->seq_len;
  edict->num_rules = dict->num_rules;
  edict->comp_seq = dict->comp_seq;
  edict->rule  = dict->rule;
  edict->tcode = (CODE*)malloc(sizeof(CODE)*dict->num_rules);

  for (i = 0; i <= CHAR_SIZE; i++) {
    edict->tcode[i] = i;
  }
  for (i = CHAR_SIZE+1; i < dict->num_rules; i++) {
    edict->tcode[i] = DUMMY_CODE;
  }

  free(dict);
  return edict;
}

int main(int argc, char *argv[])
{
  char *target_filename;
  char *output_filename;
  FILE *input, *output;
  DICT *dict;
  EDICT *edict;

  if (argc != 3) {
    printf("usage: %s target_text_file output_file\n", argv[0]);
    exit(1);
  }
  target_filename = argv[1];
  output_filename = argv[2];
  
  input  = fopen(target_filename, "r");
  output = fopen(output_filename, "wb");
  if (input == NULL || output == NULL) {
    puts("File open error at the beginning.");
    exit(1);
  }

  dict = RunRepair(input);
  edict = convertDict(dict);
  EncodeCFG(edict, output);
  DestructEDict(edict);

  fclose(input);
  fclose(output);
  exit(0);
}
#endif

#ifdef ENC2TXT
#include "decoder.h"
int main(int argc, char *argv[])
{
  FILE *input, *output;

  if (argc != 3) {
    printf("usage: %s target_enc_file output_txt_file\n", argv[0]);
    puts("argument error.");
    exit(1);
  }
  input = fopen(argv[1], "rb");
  output = fopen(argv[2], "w");
  if (input == NULL || output == NULL) {
    printf("File open error.\n");
    exit(1);
  }
  DecodeCFG(input, output);
  fclose(input); fclose(output);
  exit(0);
}
#endif

#ifdef TXT2CFG
#include "repair.h"

int main(int argc, char *argv[])
{
  char *target_filename;
  char *output_filename;
  FILE *input, *output;
  DICT *dict;

  if (argc != 3) {
    printf("usage: %s target_text_file output_file\n", argv[0]);
    exit(1);
  }
  target_filename = argv[1];
  output_filename = argv[2];
  
  input  = fopen(target_filename, "r");
  output = fopen(output_filename, "wb");
  if (input == NULL || output == NULL) {
    puts("File open error at the beginning.");
    exit(1);
  }

  dict = RunRepair(input);
  OutputGeneratedCFG(dict, output);
  DestructDict(dict);

  fclose(input);
  fclose(output);
  exit(0);
}
#endif

#if CFG2ENC
#include "encoder.h"

int main(int argc, char *argv[])
{
  FILE *input, *output;
  EDICT *dict;

  if (argc != 3) {
    printf("usage: %s target_cfg_file output_enc_file\n", argv[0]);
    exit(1);
  }
  input = fopen(argv[1], "rb");
  output = fopen(argv[2], "wb");
  if (input == NULL || output == NULL) {
    printf("File open error.\n");
    exit(1);
  }
  dict = ReadCFG(input);
  EncodeCFG(dict, output);
  DestructEDict(dict);
  fclose(input); fclose(output);
  exit(0);
}
#endif
