#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>

static int failures = 0;

static void check(int condition, const char *name) {
    if (!condition) {
        printf("FAIL: %s\n", name);
        failures++;
    }
}

int main(void) {
    char first[128];
    char second[128];
    char overlap[16];
    char tokens[32];
    char bounded[8];
    char *token;
    int result;

    strcpy(first, "MINI-OS");
    check(strlen(first) == 7U && strcmp(first, "MINI-OS") == 0,
          "strcpy and strlen");
    strcat(first, " Runtime");
    check(strcmp(first, "MINI-OS Runtime") == 0, "strcat and strcmp");
    memset(bounded, 'X', sizeof(bounded));
    strncpy(bounded, "abc", 5U);
    check(memcmp(bounded, "abc\0\0", 5U) == 0 && bounded[5] == 'X',
          "strncpy padding");
    strcpy(bounded, "ab");
    strncat(bounded, "cdef", 2U);
    check(strcmp(bounded, "abcd") == 0, "strncat bound");
    check(strncmp(first, "MINI", 4) == 0 && strncmp(first, "MINK", 4) < 0,
          "strncmp ordering");
    check(strchr(first, 'R') == first + 8 && strrchr(first, 'I') == first + 3,
          "strchr and strrchr");
    check(strstr(first, "Runtime") == first + 8 && strstr(first, "missing") == NULL,
          "strstr");

    memset(second, 0, sizeof(second));
    memcpy(second, first, strlen(first) + 1U);
    check(memcmp(second, first, strlen(first) + 1U) == 0, "memcpy and memcmp");
    check(memchr(second, ' ', strlen(second)) == second + 7, "memchr");
    strcpy(overlap, "abcdef");
    memmove(overlap + 2, overlap, 6U);
    check(memcmp(overlap, "ababcdef", 8U) == 0, "overlapping memmove");

    check(isalpha('A') && isdigit('5') && isalnum('z') && isspace('\n'),
          "ctype positive cases");
    check(!isalpha('5') && !isdigit('x') && ispunct('!') && isxdigit('F'),
          "ctype negative and punctuation cases");
    check(tolower('M') == 'm' && toupper('o') == 'O' && iscntrl(127),
          "ctype conversion and control");
    check(islower('z') && isupper('A') && isprint(' ') && !isgraph(' ') &&
          isgraph('!'), "ctype case and printable classes");

    strcpy(tokens, "apple,banana,,orange");
    token = strtok(tokens, ",");
    check(token != NULL && strcmp(token, "apple") == 0, "strtok token 1");
    token = strtok(NULL, ",");
    check(token != NULL && strcmp(token, "banana") == 0, "strtok token 2");
    token = strtok(NULL, ",");
    check(token != NULL && strcmp(token, "orange") == 0, "strtok token 3");
    check(strtok(NULL, ",") == NULL, "strtok terminates");

    result = sprintf(first, "%c %s %d %i %u %x %p %% %ld %lu %lx",
                     'Q', "ok", -12, 34, 56U, 0xABU, (void *)0x1234,
                     -78L, 90UL, 0xCDUL);
    check(result == 34 &&
          strcmp(first, "Q ok -12 34 56 ab 1234 % -78 90 cd") == 0,
          "supported format conversions");

    memset(second, 'X', sizeof(second));
    result = snprintf(second, 5U, "%s", "abcdef");
    check(result == 6 && strcmp(second, "abcd") == 0 && second[5] == 'X',
          "bounded snprintf");
    check(snprintf(NULL, 0U, "abcdef") == 6, "snprintf size zero");
    snprintf(second, sizeof(second), "%d", INT_MIN);
    check(strcmp(second, "-2147483648") == 0, "INT_MIN formatting");
    result = snprintf(second, sizeof(second), "%q");
    check(result == 2 && strcmp(second, "%q") == 0,
          "unsupported conversion is emitted literally");

    if (failures == 0) {
        puts("STRING/FORMAT TESTS PASSED");
        return 0;
    }
    printf("STRING/FORMAT FAILURES: %d\n", failures);
    return 1;
}
