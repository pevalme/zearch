/*

re-pair --  A dictionary-based compression based on the recursive paring.
Copyright (C) 2011-current_year Shirou Maruyama

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

Author's contact: Shirou Maruyama, Dept. of Informatics, Kyushu University. 744 Nishi-ku, Fukuoka-shi, Fukuoka 819-0375, Japan. shiro.maruyama@i.kyushu-u.ac.jp

*/

#include <assert.h>
#include "repair.h" 

PAIR *locatePair(RDS *rds, CODE left, CODE right);
void reconstructHash(RDS *rds);
void insertPair_PQ(RDS *rds, PAIR *target, uint p_num);
void removePair_PQ(RDS *rds, PAIR *target, uint p_num);
void incrementPair(RDS *rds, PAIR *target);
void decrementPair(RDS *rds, PAIR *target);
PAIR *createPair(RDS *rds, CODE left, CODE right, uint f_pos);
void destructPair(RDS *rds, PAIR *target);
void resetPQ(RDS *rds, uint p_num);
void initRDS(RDS *rds);
RDS *createRDS(FILE *input);
void destructRDS(RDS *rds);
PAIR *getMaxPair(RDS *rds);
uint leftPos_SQ(RDS *rds, uint pos);
uint rightPos_SQ(RDS *rds, uint pos);
void removeLink_SQ(RDS *rds, uint target_pos);
void updateBlock_SQ(RDS *rds, CODE new_code, uint target_pos);
uint replacePairs(RDS *rds, PAIR *max_pair, CODE new_code);
DICT *createDict(uint txt_len);
CODE addNewPair(DICT *dict, PAIR *max_pair);
void getCompSeq(RDS *rds, DICT *dict);

#if true
#define hash_val(P, A, B) (((A)*(B))%primes[P])
#else
uint hash_val(uint h_num, CODE left, CODE right) {
  return (left * right) % primes[h_num];
}
#endif

PAIR *locatePair(RDS *rds, CODE left, CODE right) {
  uint h = hash_val(rds->h_num, left, right);
  PAIR *p = rds->h_first[h];

  while (p != NULL) {
    if (p->left == left && p->right == right) {
      return  p;
    }
    p = p->h_next;
  }
  return NULL;
}

void reconstructHash(RDS *rds)
{
  PAIR *p, *q;
  uint i, h;

  rds->h_num++;
  rds->h_first =  
    (PAIR**)realloc(rds->h_first, sizeof(PAIR*)*primes[rds->h_num]);
  for (i = 0; i < primes[rds->h_num]; i++) {
    rds->h_first[i] = NULL;
  }
  for (i = 1; ; i++) {
    if (i == rds->p_max) i = 0;
    p = rds->p_que[i];
    while (p != NULL) {
      p->h_next = NULL;
      h = hash_val(rds->h_num, p->left, p->right);
      q = rds->h_first[h];
      rds->h_first[h] = p;
      p->h_next = q;
      p = p->p_next;
    }
    if (i == 0) break;
  }
}

void insertPair_PQ(RDS *rds, PAIR *target, uint p_num)
{
  PAIR *tmp;

  if (p_num >= rds->p_max) {
    p_num = 0;
  }

  tmp = rds->p_que[p_num];
  rds->p_que[p_num] = target;
  target->p_prev = NULL;
  target->p_next = tmp;
  if (tmp != NULL) {
    tmp->p_prev = target;
  }
}

void removePair_PQ(RDS *rds, PAIR *target, uint p_num)
{
  if (p_num >= rds->p_max) {
    p_num = 0;
  }
  
  if (target->p_prev == NULL) {
    rds->p_que[p_num] = target->p_next;
    if (target->p_next != NULL) {
      target->p_next->p_prev = NULL;
    }
  }
  else {
    target->p_prev->p_next = target->p_next;
    if (target->p_next != NULL) {
      target->p_next->p_prev = target->p_prev;
    }
  }
}

void incrementPair(RDS *rds, PAIR *target)
{
  if (target->freq >= rds->p_max) {
    target->freq++;
    return;
  }
  removePair_PQ(rds, target, target->freq);
  target->freq++;
  insertPair_PQ(rds, target, target->freq);
}

void decrementPair(RDS *rds, PAIR *target)
{
  uint h;

  if (target->freq > rds->p_max) {
    target->freq--;
    return;
  }
  
  if (target->freq == 1) {
    destructPair(rds, target);
  }
  else {
    removePair_PQ(rds, target, target->freq);
    target->freq--;
    insertPair_PQ(rds, target, target->freq);
  }
}

PAIR *createPair(RDS *rds, CODE left, CODE right, uint f_pos)
{
  PAIR *pair = (PAIR*)malloc(sizeof(PAIR));
  uint h;
  PAIR *q;
  uint i;

  pair->left  = left;
  pair->right = right;
  pair->freq = 1;
  pair->f_pos = pair->b_pos = f_pos;
  pair->p_prev = pair->p_next = NULL;

  rds->num_pairs++;

  if (rds->num_pairs >= primes[rds->h_num]) {
    reconstructHash(rds);
  }

  h = hash_val(rds->h_num, left, right);
  q = rds->h_first[h];
  rds->h_first[h] = pair;
  pair->h_next = q;
  
  insertPair_PQ(rds, pair, 1);

  return pair;
}

void destructPair(RDS *rds, PAIR *target)
{
  uint h = hash_val(rds->h_num, target->left, target->right);
  PAIR *p = rds->h_first[h];
  PAIR *q = NULL;

  removePair_PQ(rds, target, target->freq);

  while (p != NULL) {
    if (p->left == target->left && p->right == target->right) {
      break;
    }
    q = p;
    p = p->h_next;
  }

  assert(p != NULL);

  if (q == NULL) {
    rds->h_first[h] = p->h_next;
  }
  else {
    q->h_next = p->h_next;
  }
  free(target);
  rds->num_pairs--;
}

void resetPQ(RDS *rds, uint p_num)
{
  PAIR **p_que = rds->p_que;
  PAIR *pair = p_que[p_num];
  PAIR *q;
  p_que[p_num] = NULL;
  while (pair != NULL) {
    q = pair->p_next;
    destructPair(rds, pair);
    pair = q;
  }
}

void initRDS(RDS *rds)
{
  uint i;
  SEQ *seq = rds->seq;
  uint size_w = rds->txt_len;
  CODE A, B;
  PAIR *pair;
  PAIR **p_que = rds->p_que;

  for (i = 0; i < size_w - 1; i++) {
    A = seq[i].code;
    B = seq[i+1].code;
    if ((pair = locatePair(rds, A, B)) == NULL) {
      pair = createPair(rds, A, B, i);
    }
    else {
      seq[i].prev = pair->b_pos;
      seq[i].next = DUMMY_POS;
      seq[pair->b_pos].next = i;
      pair->b_pos = i;
      incrementPair(rds, pair);
    }
  }
  resetPQ(rds, 1);
}

RDS *createRDS(FILE *input)
{
  uint size_w;
  uint i;
  SEQ *seq;
  CODE c;
  uint h_num;
  PAIR **h_first;
  uint p_max;
  PAIR **p_que;
  PAIR *pair;
  RDS *rds;

  fseek(input,0,SEEK_END);
  size_w = ftell(input);
  rewind(input);
  seq = (SEQ*)malloc(sizeof(SEQ)*size_w);

  printf("text size = %d(bytes)\n", size_w);

  i = 0;
  while ((c = getc(input)) != EOF) {
    seq[i].code = c;
    seq[i].next = DUMMY_POS;
    seq[i].prev = DUMMY_POS;
    i++;
  }

  h_num = INIT_HASH_NUM;
  h_first = (PAIR**)malloc(sizeof(PAIR*)*primes[h_num]);
  for (i = 0; i < primes[h_num]; i++) {
    h_first[i] = NULL;
  }

  p_max = (uint)ceil(sqrt((double)size_w));
  p_que = (PAIR**)malloc(sizeof(PAIR*)*p_max);
  for (i = 0; i < p_max; i++) {
    p_que[i] = NULL;
  }
  
  rds = (RDS*)malloc(sizeof(RDS));
  rds->txt_len = size_w;
  rds->seq = seq;
  rds->num_pairs = 0;
  rds->h_num = h_num;
  rds->h_first = h_first;
  rds->p_max = p_max;
  rds->p_que = p_que;
  initRDS(rds);

  return rds;
}

void destructRDS(RDS *rds)
{
  PAIR *p, *q;
  uint i;

  free(rds->seq);
  free(rds->h_first);
  free(rds->p_que);
  free(rds);
}

PAIR *getMaxPair(RDS *rds)
{
  static uint i = 0;
  PAIR **p_que = rds->p_que;
  PAIR *p, *max_pair;
  uint max;

  if (p_que[0] != NULL) {
    p = p_que[0];
    max = 0; max_pair = NULL;
    while (p != NULL) {
      if (max < p->freq) {
	max = p->freq;
	max_pair = p;
      }
      p = p->p_next;
    }
  }
  else {
    max_pair = NULL;
    if (i == 0) i = rds->p_max-1;
    for (; i > 1; i--) {
      if (p_que[i] != NULL) {
	max_pair = p_que[i];
	break;
      }
    }
  }
  return max_pair;
}

uint leftPos_SQ(RDS *rds, uint pos)
{
  SEQ *seq = rds->seq;

  assert(pos != DUMMY_POS);
  if (pos == 0) {
    return DUMMY_POS;
  }

  if (seq[pos-1].code == DUMMY_CODE) {
    return seq[pos-1].next;
  }
  else {
    return pos-1;
  }
}

uint rightPos_SQ(RDS *rds, uint pos)
{
  SEQ *seq = rds->seq;

  assert(pos != DUMMY_POS);
  if (pos == rds->txt_len-1) {
    return DUMMY_POS;
  }

  if (seq[pos+1].code == DUMMY_CODE) {
    return seq[pos+1].prev;
  }
  else {
    return pos+1;
  }
}

void removeLink_SQ(RDS *rds, uint target_pos)
{
  SEQ *seq = rds->seq;
  uint prev_pos, next_pos;

  assert(seq[target_pos].code != DUMMY_CODE);

  prev_pos = seq[target_pos].prev;
  next_pos = seq[target_pos].next;

  if (prev_pos != DUMMY_POS && next_pos != DUMMY_POS) {
    seq[prev_pos].next = next_pos;
    seq[next_pos].prev = prev_pos;
  }
  else if (prev_pos == DUMMY_POS && next_pos != DUMMY_POS) {
    seq[next_pos].prev = DUMMY_POS;
  }
  else if (prev_pos != DUMMY_POS && next_pos == DUMMY_POS) {
    seq[prev_pos].next = DUMMY_POS;
  }
}

void updateBlock_SQ(RDS *rds, CODE new_code, uint target_pos)
{
  SEQ *seq = rds->seq;
  uint l_pos, r_pos, rr_pos, nx_pos;
  CODE c_code, r_code, l_code, rr_code;
  PAIR *l_pair, *c_pair, *r_pair;
  uint i, j;

  l_pos  = leftPos_SQ(rds, target_pos);
  r_pos  = rightPos_SQ(rds, target_pos);
  rr_pos = rightPos_SQ(rds, r_pos);
  c_code = seq[target_pos].code;
  r_code = seq[r_pos].code;

  nx_pos = seq[target_pos].next;
  if (nx_pos == r_pos) {
    nx_pos = seq[nx_pos].next;
  }

  assert(c_code != DUMMY_CODE);
  assert(r_code != DUMMY_CODE);

  if (l_pos != DUMMY_POS) {
    l_code = seq[l_pos].code;
    assert(seq[l_pos].code != DUMMY_CODE);
    removeLink_SQ(rds, l_pos);
    if ((l_pair = locatePair(rds, l_code, c_code)) != NULL) {
      if (l_pair->f_pos == l_pos) {
	l_pair->f_pos = seq[l_pos].next;
      }
      decrementPair(rds, l_pair);
    }
    if ((l_pair = locatePair(rds, l_code, new_code)) == NULL) {
      seq[l_pos].prev = DUMMY_POS;
      seq[l_pos].next = DUMMY_POS;
      createPair(rds, l_code, new_code, l_pos);
    }
    else {
      seq[l_pos].prev = l_pair->b_pos;
      seq[l_pos].next = DUMMY_POS;
      seq[l_pair->b_pos].next = l_pos;
      l_pair->b_pos = l_pos;
      incrementPair(rds, l_pair);
    }
  }

  removeLink_SQ(rds, target_pos);
  removeLink_SQ(rds, r_pos);
  seq[target_pos].code = new_code;
  seq[r_pos].code = DUMMY_CODE;
  
  if (rr_pos != DUMMY_POS) {
    rr_code = seq[rr_pos].code;
    assert(rr_code != DUMMY_CODE);
    if ((r_pair = locatePair(rds, r_code, rr_code)) != NULL) {
      if (r_pair->f_pos == r_pos) {
	r_pair->f_pos = seq[r_pos].next;
      }
      decrementPair(rds, r_pair);
    }

    if (target_pos+1 == rr_pos-1) {
      seq[target_pos+1].prev = rr_pos;
      seq[target_pos+1].next = target_pos;
    }
    else {
      seq[target_pos+1].prev = rr_pos;
      seq[target_pos+1].next = DUMMY_POS;
      seq[rr_pos-1].prev = DUMMY_POS;
      seq[rr_pos-1].next = target_pos;
    }
    /*
    if (seq[target_pos+2].code == DUMMY_CODE) {
      if( target_pos+2 < rr_pos-1) {
	seq[target_pos+2].prev = seq[target_pos+2].next = DUMMY_POS;
      }
    }
    if (seq[rr_pos-2].code == DUMMY_CODE) { 
      if (rr_pos-2 > target_pos+1) {
	seq[rr_pos-2].prev = seq[rr_pos-2].next = DUMMY_POS;
      }
    }
    */
    if (nx_pos > rr_pos) {
      if ((c_pair = locatePair(rds, new_code, rr_code)) == NULL) {
	seq[target_pos].prev = seq[target_pos].next = DUMMY_POS;
	createPair(rds, new_code, rr_code, target_pos);
      }
      else {
	seq[target_pos].prev = c_pair->b_pos;
	seq[target_pos].next = DUMMY_POS;
	seq[c_pair->b_pos].next = target_pos;
	c_pair->b_pos = target_pos;
	incrementPair(rds, c_pair);
      }
    }
    else {
      seq[target_pos].next = seq[target_pos].prev = DUMMY_POS;
    }
  }
  else if (target_pos < rds->txt_len - 1) {
    assert(seq[target_pos+1].code == DUMMY_CODE);
    seq[target_pos+1].prev = DUMMY_POS;
    seq[target_pos+1].next = target_pos;
    seq[r_pos].prev = seq[r_pos].next = DUMMY_POS;
  }
}

uint replacePairs(RDS *rds, PAIR *max_pair, CODE new_code)
{
  uint i, j;
  uint num_replaced = 0;
  SEQ *seq = rds->seq;

  i = max_pair->f_pos;
  while (i != DUMMY_POS) {
    j = seq[i].next;
    if (j == rightPos_SQ(rds, i)) {
      j = seq[j].next;
    }
    updateBlock_SQ(rds, new_code, i);
    i = j;
    num_replaced++;
  }

  if (max_pair->freq != 1) { 
    destructPair(rds, max_pair); 
  }
  resetPQ(rds, 1);
  return num_replaced;
}

DICT *createDict(uint txt_len)
{
  uint i;
  DICT *dict = (DICT*)malloc(sizeof(DICT));
  dict->txt_len = txt_len;
  dict->buff_size = INIT_DICTIONARY_SIZE;
  dict->rule = (RULE*)malloc(sizeof(RULE)*dict->buff_size);
  dict->seq_len = 0;
  dict->comp_seq = NULL;
  dict->num_rules = 0;

  for (i = 0; i < dict->buff_size; i++) {
    dict->rule[i].left = DUMMY_CODE;
    dict->rule[i].right = DUMMY_CODE;
  }

  for (i = 0; i < CHAR_SIZE+1; i++) {
    dict->rule[i].left  = (CODE)i;
    dict->rule[i].right = DUMMY_CODE;
    dict->num_rules++;
  }

  return dict;
}

CODE addNewPair(DICT *dict, PAIR *max_pair)
{
  RULE *rule = dict->rule;
  CODE new_code = dict->num_rules++;

  rule[new_code].left = max_pair->left;
  rule[new_code].right = max_pair->right;

  if (dict->num_rules >= dict->buff_size) {
    dict->buff_size *= DICTIONARY_SCALING_FACTOR;
    dict->rule = (RULE*)realloc(dict->rule, sizeof(RULE)*dict->buff_size);
    if (dict->rule == NULL) {
      puts("Memory reallocate error (rule) at addDict.");
      exit(1);
    }
  }
  return new_code;
}

void getCompSeq(RDS *rds, DICT *dict)
{
  uint i, j;
  SEQ *seq = rds->seq;
  uint seq_len;
  CODE *comp_seq;

  i = 0; seq_len = 0;
  while (i < rds->txt_len) {
    if (seq[i].code == DUMMY_CODE) {
      i = seq[i].prev;
      continue;
    }
    seq_len++;
    i++;
  }

  comp_seq = (CODE*)malloc(sizeof(CODE)*seq_len);
  i = j = 0;
  while (i < rds->txt_len) {
    if (seq[i].code == DUMMY_CODE) {
      i = seq[i].prev;
      continue;
    }
    comp_seq[j++] = seq[i].code;
    i++;
  }
  dict->comp_seq = comp_seq;
  dict->seq_len = seq_len;
}

DICT *RunRepair(FILE *input)
{
  RDS  *rds;
  DICT *dict;
  PAIR *max_pair;
  CODE new_code;
  uint num_loop, num_replaced;

  rds  = createRDS(input);
  dict = createDict(rds->txt_len);

  printf("Generating CFG..."); fflush(stdout);
  num_loop = 0; num_replaced = 0;
  while ((max_pair = getMaxPair(rds)) != NULL) {
    new_code = addNewPair(dict, max_pair);
    //if (new_code > USHRT_MAX) break;
    num_replaced += replacePairs(rds, max_pair, new_code);
  }
  getCompSeq(rds, dict);
  destructRDS(rds);
  printf("Finished!\n"); fflush(stdout);

  return dict;
}

void DestructDict(DICT *dict)
{
  free(dict->rule);
  free(dict->comp_seq);
  free(dict);
}

void OutputGeneratedCFG(DICT *dict, FILE *output)
{
  uint txt_len = dict->txt_len;
  uint num_rules = dict->num_rules;
  uint seq_len = dict->seq_len;

  printf("num_rules = %d\n", num_rules);
  printf("seq_len = %d\n", seq_len);

  fwrite(&txt_len, sizeof(uint), 1, output);
  fwrite(&num_rules, sizeof(uint), 1, output);
  fwrite(&seq_len, sizeof(uint), 1, output);
  fwrite(dict->rule+CHAR_SIZE+1, sizeof(RULE), num_rules-(CHAR_SIZE+1), output);
  fwrite(dict->comp_seq, sizeof(CODE), seq_len, output);
}

