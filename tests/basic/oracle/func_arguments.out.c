struct S {
  int x;
  int y;
};

int f_with_arg(struct S *s) {
  return s->x;
}

/*@
  requires s->x >= 0;
  ensures \result == \old(s->x);
*/
int start(struct S *s) {
  return f_with_arg(s);
}

void __CPROVER_assume(_Bool);void __CPROVER_assert(_Bool, const char *);
void acta_harness_start(void)
{
  // Harness parameters are left symbolic for CBMC.
  struct S * s;
  
  // requires -> __CPROVER_assume
  __CPROVER_assume(s->x >= 0);
  
  // Pre-state snapshots used by ensures.
  struct S * s_old = s;
  
  int start_result = start(s);
  
  // ensures -> __CPROVER_assert
  __CPROVER_assert(start_result == s_old->x, "ensures");
  
}
