int a;

/*@
  ensures a > 0 ==> \result == a;
*/
int func(void) {
  return (a > 0) ? a : 0;
}

void __CPROVER_assume(_Bool);void __CPROVER_assert(_Bool, const char *);
void acta_harness_func(void)
{
  
  
  
  int func_result = func();
  
  // ensures -> __CPROVER_assert
  __CPROVER_assert(!(a > 0) || func_result == a, "ensures");
  
}
