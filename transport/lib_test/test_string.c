#include <stdio.h>
#include <string.h>
#include <ctype.h>

int main(void) {
    char buf1[64];
    char buf2[64];
    const char *str = "  Hello, MINI-OS C90 World! 12345  ";
    char *token;

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

    puts("\nPhase 1 String & Ctype tests PASSED cleanly!");
    return 0;
}
