/*@ predicate nonnegative(integer value) = value >= 0; */

/*@ requires nonnegative(x);
    ensures \result == x;
*/
int identity(int x)
{
    return x;
}
