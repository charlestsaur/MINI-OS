#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int compare_ints(const void *a, const void *b) {
    int arg1 = *(const int *)a;
    int arg2 = *(const int *)b;
    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

int main(void) {
    int *arr;
    int i;
    size_t count = 8;

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

    puts("\nPhase 2 Heap & Stdlib tests PASSED cleanly!");
    return 0;
}
