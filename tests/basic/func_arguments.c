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
