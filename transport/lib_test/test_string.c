#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>

int main(void) {
    char buf1[64];
    char buf2[64];
    char *token;
    int result;

    puts("==========================================");
    puts("   MINI-OS Phase 1 String & Ctype Test");
    puts("==========================================");

    /* 1. Test strcpy & strlen */
    strcpy(buf1, "MINI-OS");
    printf("1. strcpy: '%s' (len: %u)\n", buf1, (unsigned int)strlen(buf1));

    /* 2. Test strcat & strcmp */
    strcat(buf1, " Runtime");
    printf("2. strcat: '%s'\n", buf1);
    printf("3. strcmp('MINI-OS Runtime', '%s'): %d\n", buf1, strcmp("MINI-OS Runtime", buf1));

    /* 3. Test strchr & strstr */
    printf("4. strchr('%s', 'R'): '%s'\n", buf1, strchr(buf1, 'R'));
    printf("5. strstr('%s', 'Time'): '%s'\n", buf1, strstr(buf1, "Runtime"));

    /* 4. Test memset & memcpy */
    memset(buf2, 0, sizeof(buf2));
    memcpy(buf2, buf1, strlen(buf1));
    printf("6. memcpy: '%s'\n", buf2);

    /* 5. Test ctype functions */
    printf("7. isalpha('A'): %d, isdigit('5'): %d, isspace(' '): %d\n",
           isalpha('A'), isdigit('5'), isspace(' '));
    printf("8. tolower('M'): '%c', toupper('o'): '%c'\n",
           tolower('M'), toupper('o'));

    /* 6. Test strtok */
    strcpy(buf2, "apple,banana,orange,grape");
    puts("9. strtok split 'apple,banana,orange,grape':");
    token = strtok(buf2, ",");
    while (token != NULL) {
        printf("   - %s\n", token);
        token = strtok(NULL, ",");
    }

    memset(buf2, 'X', sizeof(buf2));
    result = snprintf(buf2, 5, "%s", "abcdef");
    if (result != 6 || strcmp(buf2, "abcd") != 0 || buf2[5] != 'X') {
        puts("FAIL: bounded snprintf");
        return 1;
    }
    if (snprintf(NULL, 0, "abcdef") != 6) {
        puts("FAIL: snprintf size zero");
        return 1;
    }
    snprintf(buf2, sizeof(buf2), "%d", INT_MIN);
    if (strcmp(buf2, "-2147483648") != 0) {
        puts("FAIL: INT_MIN formatting");
        return 1;
    }
    result = printf("10. printf count probe");
    if (result != 22) {
        puts("\nFAIL: printf return value");
        return 1;
    }
    putchar('\n');

    puts("STRING/FORMAT TESTS PASSED");
    return 0;
}
