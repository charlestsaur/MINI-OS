#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

struct large_item {
    int key;
    char padding[300];
};

static int failures = 0;

static void check(int condition, const char *name) {
    if (!condition) {
        printf("FAIL: %s\n", name);
        failures++;
    }
}

static int compare_ints(const void *left, const void *right) {
    int a = *(const int *)left;
    int b = *(const int *)right;
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

static int compare_large_items(const void *left, const void *right) {
    const struct large_item *a = (const struct large_item *)left;
    const struct large_item *b = (const struct large_item *)right;
    if (a->key < b->key) return -1;
    if (a->key > b->key) return 1;
    return 0;
}

int main(void) {
    static const int expected_sorted[8] = {0, 33, 56, 61, 69, 77, 81, 93};
    int *values;
    int *found;
    int *zeros;
    int i;
    char *end;
    struct large_item items[2];
    void *blocks[64];
    int allocated;

    values = (int *)malloc(8U * sizeof(int));
    check(values != NULL, "malloc");
    if (values == NULL) return 1;

    srand(42U);
    for (i = 0; i < 8; i++) values[i] = rand() % 100;
    qsort(values, 8U, sizeof(int), compare_ints);
    check(memcmp(values, expected_sorted, sizeof(expected_sorted)) == 0,
          "rand sequence and qsort result");

    values = (int *)realloc(values, 16U * sizeof(int));
    check(values != NULL, "realloc growth");
    if (values == NULL) return 1;
    check(memcmp(values, expected_sorted, sizeof(expected_sorted)) == 0,
          "realloc preserves contents");
    free(values);

    zeros = (int *)calloc(16U, sizeof(int));
    check(zeros != NULL, "calloc");
    if (zeros != NULL) {
        for (i = 0; i < 16; i++) check(zeros[i] == 0, "calloc zero byte range");
        free(zeros);
    }
    check(calloc(UINT_MAX, 2U) == NULL && malloc(UINT_MAX) == NULL,
          "allocation overflow rejection");

    items[0].key = 2;
    items[1].key = 1;
    memset(items[0].padding, 'A', sizeof(items[0].padding));
    memset(items[1].padding, 'B', sizeof(items[1].padding));
    qsort(items, 2U, sizeof(items[0]), compare_large_items);
    check(items[0].key == 1 && items[1].key == 2 &&
          items[0].padding[0] == 'B' && items[1].padding[0] == 'A',
          "qsort large elements");

    found = (int *)bsearch(&expected_sorted[4], expected_sorted, 8U,
                           sizeof(int), compare_ints);
    check(found != NULL && *found == 69, "bsearch hit");
    i = 70;
    check(bsearch(&i, expected_sorted, 8U, sizeof(int), compare_ints) == NULL,
          "bsearch miss");
    check(atoi(" -123x") == -123, "atoi");
    check(strtol("0x2a!", &end, 0) == 42L && *end == '!', "strtol base detection");
    check(strtoul("17z", &end, 8) == 15UL && *end == 'z', "strtoul base 8");
    check(abs(-7) == 7 && labs(-9L) == 9L, "abs and labs");

    allocated = 0;
    while (allocated < 64) {
        blocks[allocated] = malloc(4096U);
        if (blocks[allocated] == NULL) break;
        allocated++;
    }
    check(allocated < 64 && malloc(4096U) == NULL, "heap exhaustion");
    for (i = 0; i < allocated; i++) free(blocks[i]);
    values = (int *)malloc(4096U);
    check(values != NULL, "freed heap is reusable");
    free(values);

    if (failures == 0) {
        puts("HEAP/STDLIB TESTS PASSED");
        return 0;
    }
    printf("HEAP/STDLIB FAILURES: %d\n", failures);
    return 1;
}
