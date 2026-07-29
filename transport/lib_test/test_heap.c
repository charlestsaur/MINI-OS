#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

struct large_item {
    int key;
    char padding[300];
};

static int compare_ints(const void *a, const void *b) {
    int arg1 = *(const int *)a;
    int arg2 = *(const int *)b;
    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

static int compare_large_items(const void *a, const void *b) {
    const struct large_item *left = (const struct large_item *)a;
    const struct large_item *right = (const struct large_item *)b;
    if (left->key < right->key) return -1;
    if (left->key > right->key) return 1;
    return 0;
}

int main(void) {
    int *arr;
    int i;
    size_t count = 8;
    struct large_item items[2];
    void *blocks[64];
    int allocated;

    puts("==========================================");
    puts("   MINI-OS Phase 2 Heap & Stdlib Test");
    puts("==========================================");

    /* 1. Test malloc */
    arr = (int *)malloc(count * sizeof(int));
    if (!arr) {
        puts("ERROR: malloc returned NULL!");
        return 1;
    }
    printf("1. malloc(%u bytes) successful at %p\n",
           (unsigned int)(count * sizeof(int)), (void *)arr);

    /* 2. Test rand & array populate */
    srand(42);
    for (i = 0; i < (int)count; i++) {
        arr[i] = rand() % 100;
    }

    printf("2. Random array before qsort: ");
    for (i = 0; i < (int)count; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");

    /* 3. Test qsort */
    qsort(arr, count, sizeof(int), compare_ints);
    printf("3. Array after qsort:         ");
    for (i = 0; i < (int)count; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");

    /* 4. Test realloc */
    arr = (int *)realloc(arr, (count * 2) * sizeof(int));
    if (!arr) {
        puts("ERROR: realloc failed!");
        return 1;
    }
    printf("4. realloc to %u bytes successful at %p\n",
           (unsigned int)(count * 2 * sizeof(int)), (void *)arr);

    /* 5. Test free */
    free(arr);
    puts("5. free(arr) completed.");

    items[0].key = 2;
    items[1].key = 1;
    qsort(items, 2, sizeof(items[0]), compare_large_items);
    if (items[0].key != 1 || items[1].key != 2) {
        puts("FAIL: qsort large elements");
        return 1;
    }

    if (calloc(UINT_MAX, 2) != NULL || malloc(UINT_MAX) != NULL) {
        puts("FAIL: allocation overflow");
        return 1;
    }

    allocated = 0;
    while (allocated < 64) {
        blocks[allocated] = malloc(4096);
        if (blocks[allocated] == NULL) break;
        allocated++;
    }
    if (allocated == 64 || malloc(4096) != NULL) {
        puts("FAIL: heap exhaustion");
        return 1;
    }
    for (i = 0; i < allocated; i++) free(blocks[i]);

    puts("HEAP/STDLIB TESTS PASSED");
    return 0;
}
