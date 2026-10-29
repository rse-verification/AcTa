/*@ predicate nonnegative(integer value) = value >= 0; */

/*@ requires nonnegative(x);
    ensures \result == x;
*/
int identity(int x)
{
    return x;
}

void __CPROVER_assume(_Bool);void __CPROVER_assert(_Bool, const char *);
void acta_harness_identity(void)
{
  // Harness parameters are left symbolic for CBMC.
  int x;
  
  // requires -> __CPROVER_assume
  __CPROVER_assume(x >= 0);
  
  // Pre-state snapshots used by ensures.
  int x_old = x;
  
  int identity_result = identity(x);
  
  // ensures -> __CPROVER_assert
  __CPROVER_assert(identity_result == x_old, "ensures");
  
}
