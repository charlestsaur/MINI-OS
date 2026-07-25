#include <stdio.h>
#include <string.h>
#include <ctype.h>

#define MAX_LEN 256
#define FONT_HEIGHT 5
#define FONT_WIDTH 5

/* 
 * 5x5 Matrix Font Definition (A-Z, 0-9)
 * Each row uses a 5-bit binary pattern (expressed in hexadecimal):
 * 1 represents character pixel '#', 0 represents space ' '
 */
static const unsigned char font_letters[26][FONT_HEIGHT] = {
    {0x0E, 0x11, 0x1F, 0x11, 0x11}, /* A */
    {0x1E, 0x11, 0x1E, 0x11, 0x1E}, /* B */
    {0x0E, 0x11, 0x10, 0x11, 0x0E}, /* C */
    {0x1C, 0x12, 0x12, 0x12, 0x1C}, /* D */
    {0x1F, 0x10, 0x1E, 0x10, 0x1F}, /* E */
    {0x1F, 0x10, 0x1E, 0x10, 0x10}, /* F */
    {0x0E, 0x10, 0x13, 0x11, 0x0F}, /* G */
    {0x11, 0x11, 0x1F, 0x11, 0x11}, /* H */
    {0x0E, 0x04, 0x04, 0x04, 0x0E}, /* I */
    {0x07, 0x02, 0x02, 0x12, 0x0C}, /* J */
    {0x11, 0x12, 0x1C, 0x12, 0x11}, /* K */
    {0x10, 0x10, 0x10, 0x10, 0x1F}, /* L */
    {0x11, 0x1B, 0x15, 0x11, 0x11}, /* M */
    {0x11, 0x19, 0x15, 0x13, 0x11}, /* N */
    {0x0E, 0x11, 0x11, 0x11, 0x0E}, /* O */
    {0x1E, 0x11, 0x1E, 0x10, 0x10}, /* P */
    {0x0E, 0x11, 0x11, 0x15, 0x0E}, /* Q */
    {0x1E, 0x11, 0x1E, 0x14, 0x11}, /* R */
    {0x0F, 0x10, 0x0E, 0x01, 0x1E}, /* S */
    {0x1F, 0x04, 0x04, 0x04, 0x04}, /* T */
    {0x11, 0x11, 0x11, 0x11, 0x0E}, /* U */
    {0x11, 0x11, 0x11, 0x0A, 0x04}, /* V */
    {0x11, 0x11, 0x15, 0x15, 0x0A}, /* W */
    {0x11, 0x0A, 0x04, 0x0A, 0x11}, /* X */
    {0x11, 0x11, 0x0A, 0x04, 0x04}, /* Y */
    {0x1F, 0x02, 0x04, 0x08, 0x1F}  /* Z */
};

static const unsigned char font_digits[10][FONT_HEIGHT] = {
    {0x0E, 0x11, 0x11, 0x11, 0x0E}, /* 0 */
    {0x04, 0x0C, 0x04, 0x04, 0x0E}, /* 1 */
    {0x0E, 0x01, 0x0E, 0x10, 0x1F}, /* 2 */
    {0x1F, 0x02, 0x0E, 0x01, 0x1E}, /* 3 */
    {0x02, 0x06, 0x0A, 0x1F, 0x02}, /* 4 */
    {0x1F, 0x10, 0x1E, 0x01, 0x1E}, /* 5 */
    {0x0E, 0x10, 0x1E, 0x11, 0x0E}, /* 6 */
    {0x1F, 0x01, 0x02, 0x04, 0x04}, /* 7 */
    {0x0E, 0x11, 0x0E, 0x11, 0x0E}, /* 8 */
    {0x0E, 0x11, 0x0F, 0x01, 0x0E}  /* 9 */
};

/* C90 requires all variable declarations at the start of the block */
void print_large_text(const char *text) {
    int row, col;
    size_t i, len;

    len = strlen(text);

    /* Render line by line */
    for (row = 0; row < FONT_HEIGHT; row++) {
        for (i = 0; i < len; i++) {
            char c = text[i];
            unsigned char line_data = 0x00;

            /* Match character type to bitmap data */
            if (isalpha((unsigned char)c)) {
                c = (char)toupper((unsigned char)c);
                line_data = font_letters[c - 'A'][row];
            } else if (isdigit((unsigned char)c)) {
                line_data = font_digits[c - '0'][row];
            } else {
                /* Space or unsupported characters default to blank */
                line_data = 0x00;
            }

            /* Output 5 pixels for current character on current row */
            for (col = FONT_WIDTH - 1; col >= 0; col--) {
                if ((line_data >> col) & 1) {
                    putchar('#');
                } else {
                    putchar(' ');
                }
            }

            /* Character spacing */
            putchar(' ');
        }
        putchar('\n');
    }
}

int main(void) {
    char name[MAX_LEN];

    printf("Enter a name: ");
    if (fgets(name, sizeof(name), stdin) != NULL) {
        /* Strip trailing newline character */
        size_t len = strlen(name);
        if (len > 0 && name[len - 1] == '\n') {
            name[len - 1] = '\0';
        }

        printf("\n--- Banner Output ---\n\n");
        print_large_text(name);
        printf("\n");
    }

    return 0;
}
