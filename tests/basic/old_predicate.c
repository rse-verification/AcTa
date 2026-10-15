int g;

int add_one(int x) {
  return x + 1;
}

/*@
  requires 100 >= g >= 0;
  ensures \old(g >= 0);
*/
void main(void) {
  g = add_one(g);
  g = add_one(g);
}
