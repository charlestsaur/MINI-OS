#ifndef ASSERT_H
#define ASSERT_H

#include "minilibc.h"

#ifdef NDEBUG
#define assert(ignore) ((void)0)
#else
#define assert(expr) \
    ((expr) ? (void)0 : (printf("Assertion failed: %s, file %s, line %d\n", #expr, __FILE__, __LINE__), exit(1)))
#endif

#endif
