#include <stdio.h>

static unsigned char payload[1024];

int main(void) {
    FILE *stream;
    size_t written;
    int had_error;

    stream = fopen("/no-space.tmp", "w");
    if (stream == NULL) {
        puts("NO-SPACE DIRTY TEST: OPEN FAILED");
        return 1;
    }

    written = fwrite(payload, 1U, sizeof(payload), stream);
    had_error = ferror(stream);
    fclose(stream);
    if (written != 0U || had_error == 0) {
        puts("NO-SPACE DIRTY TEST: UNEXPECTED WRITE RESULT");
        return 1;
    }

    puts("NO-SPACE DIRTY TEST: PASS");
    return 0;
}
