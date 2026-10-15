int a;

/*@
  ensures a > 0 ==> \result == a;
*/
int func(void) {
  return (a > 0) ? a : 0;
}
