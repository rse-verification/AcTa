int g;

int add_one(int x) {
  return x + 1;
}

/*@
  requires 100 >= g >= 0;
  ensures g == \old(g) + 2;
*/
void main(void) {
  g = add_one(g);
  g = add_one(g);
}

void __CPROVER_assume(_Bool);void __CPROVER_assert(_Bool, const char *);
void acta_harness_main(void)
{
  
  // requires -> __CPROVER_assume
  __CPROVER_assume(100 >= g && g >= 0);
  
  // Pre-state snapshots used by ensures.
  int g_old = g;
  
  main();
  
  // ensures -> __CPROVER_assert
  __CPROVER_assert(g == g_old + 2, "ensures");
  
}
