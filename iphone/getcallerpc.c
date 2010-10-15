#include "u.h"
#include "libc.h"

// XXX: i don't know if that is even remotely right...it hasn't yet caused any obvious troubles though
uintptr
getcallerpc(void *a)
{
	return ((uintptr*)a)[-1];
}
