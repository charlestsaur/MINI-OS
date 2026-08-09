#include <stdio.h>

#define BYTE_COUNT 8192
#define WORD_COUNT 1024

static unsigned char zero_bytes[BYTE_COUNT];
static unsigned int zero_words[WORD_COUNT];
static unsigned int initialized_marker = 0x13579BDFU;

int main(void) {
    int i;

    for (i = 0; i < BYTE_COUNT; i++) {
        if (zero_bytes[i] != 0U) {
            printf("BSS test: FAIL at byte %d\n", i);
            return 1;
        }
    }
    for (i = 0; i < WORD_COUNT; i++) {
        if (zero_words[i] != 0U) {
            printf("BSS test: FAIL at word %d\n", i);
            return 1;
        }
    }
    if (initialized_marker != 0x13579BDFU) {
        puts("BSS test: FAIL initialized data");
        return 1;
    }

    zero_bytes[BYTE_COUNT - 1] = 0xA5U;
    zero_words[WORD_COUNT - 1] = 0x5A5AA5A5U;
    if (zero_bytes[BYTE_COUNT - 1] != 0xA5U ||
        zero_words[WORD_COUNT - 1] != 0x5A5AA5A5U) {
        puts("BSS test: FAIL writable storage");
        return 1;
    }

    puts("BSS test: PASS");
    return 0;
}
