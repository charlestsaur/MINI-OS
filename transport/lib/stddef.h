#ifndef STDDEF_H
#define STDDEF_H

#include "minilibc.h"

typedef int ptrdiff_t;

#ifndef offsetof
#define offsetof(type, member) ((size_t)&(((type *)0)->member))
#endif

#endif
