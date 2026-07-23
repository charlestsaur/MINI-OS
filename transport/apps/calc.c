#include "minilibc.h"

int main(void) {
    int a = 15;
    int b = 27;
    int sum = a + b;
    int prod = a * b;

    puts("--- MINI-OS Calculator App ---");
    printf("a = %d, b = %d\n", a, b);
    printf("a + b = %d\n", sum);
    printf("a * b = %d\n", prod);
    return 0;
}
