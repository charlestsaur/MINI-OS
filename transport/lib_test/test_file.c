#include <stdio.h>
#include <string.h>
#include <limits.h>

static int failures = 0;

#define CROSS_SIZE 1300U
#define APPEND_SIZE 11U

static unsigned char cross_written[CROSS_SIZE + APPEND_SIZE];
static unsigned char cross_read[CROSS_SIZE + APPEND_SIZE];

static void check(int condition, const char *name) {
    if (!condition) {
        printf("FAIL: %s\n", name);
        failures++;
    }
}

static int call_unknown_syscall(void) {
    int result;
    __asm__ __volatile__ (
        "int $0x80"
        : "=a"(result)
        : "a"(0x7fffffff)
        : "memory"
    );
    return result;
}

int main(void) {
    FILE *fp;
    char buffer[16];
    size_t count;
    unsigned int i;
    static const char begin_marker[] = "E2E-BEGIN\n";
    static const char end_marker[] = "E2E-END\n";
    static const char append_marker[] = "E2E-APPEND\n";

    fp = fopen("syslib.txt", "w");
    check(fp != NULL, "open w");
    if (fp != NULL) {
        check(fwrite("base", 1, 4, fp) == 4, "write base");
        check(ftell(fp) == 4, "write position");
        check(fread(buffer, 1, 1, fp) == 0, "write-only read rejected");
        check(ferror(fp) != 0 && feof(fp) == 0, "read error is not EOF");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "r");
    check(fp != NULL, "open r");
    if (fp != NULL) {
        check(fwrite("+", 1, 1, fp) == 0, "read-only write rejected");
        check(ferror(fp) != 0 && feof(fp) == 0, "write error is not EOF");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "a");
    check(fp != NULL, "open a");
    if (fp != NULL) {
        check(fwrite("+", 1, 1, fp) == 1, "append write");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "r+");
    check(fp != NULL, "open r+");
    if (fp != NULL) {
        memset(buffer, 0, sizeof(buffer));
        count = fread(buffer, 1, sizeof(buffer), fp);
        check(count == 5 && memcmp(buffer, "base+", 5) == 0,
              "append preserved contents");
        check(feof(fp) != 0 && ferror(fp) == 0, "short read sets only EOF");
        check(fseek(fp, 0, SEEK_SET) == 0 && feof(fp) == 0,
              "seek clears EOF");
        check(fflush(fp) == 0, "unbuffered stream flush");
        check(fseek(fp, -1, SEEK_SET) < 0, "negative seek rejected");
        check(fseek(fp, LONG_MAX, SEEK_END) < 0,
              "overflowing seek rejected");
        rewind(fp);
        check(ftell(fp) == 0L && feof(fp) == 0, "rewind resets position and EOF");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "w+");
    check(fp != NULL, "open w+");
    if (fp != NULL) {
        check(fwrite("A", 1, 1, fp) == 1, "write after truncate");
        check(fseek(fp, 3, SEEK_SET) == 0, "seek beyond EOF");
        check(fwrite("B", 1, 1, fp) == 1, "write after gap");
        check(fseek(fp, 0, SEEK_SET) == 0, "rewind gap file");
        memset(buffer, 0x7f, sizeof(buffer));
        count = fread(buffer, 1, 4, fp);
        check(count == 4 && buffer[0] == 'A' && buffer[1] == 0 &&
              buffer[2] == 0 && buffer[3] == 'B', "gap bytes are zero");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "a+");
    check(fp != NULL, "open a+");
    if (fp != NULL) {
        check(fseek(fp, 0, SEEK_SET) == 0, "append stream seek");
        check(fwrite("C", 1, 1, fp) == 1, "append ignores write position");
        check(fseek(fp, 0, SEEK_SET) == 0, "append stream rewind");
        memset(buffer, 0, sizeof(buffer));
        count = fread(buffer, 1, 5, fp);
        check(count == 5 && buffer[4] == 'C', "append landed at EOF");
        check(fwrite(buffer, 2, UINT_MAX, fp) == 0,
              "fwrite multiplication overflow");
        check(ferror(fp) != 0, "overflow sets stream error");
        fclose(fp);
    }

    fp = fopen("syslib.txt", "r");
    check(fp != NULL, "open for fread overflow");
    if (fp != NULL) {
        check(fread(buffer, 2, UINT_MAX, fp) == 0,
              "fread multiplication overflow");
        check(ferror(fp) != 0, "fread overflow sets stream error");
        fclose(fp);
    }

    check(fopen("syslib.txt", "bad") == NULL, "invalid mode rejected");
    check(fopen("syslib.txt", "r++") == NULL, "duplicate plus mode rejected");
    check(fflush(NULL) == 0, "NULL accepted by no-op flush");

    for (i = 0U; i < CROSS_SIZE; i++) {
        cross_written[i] = (unsigned char)('a' + (i % 26U));
    }
    memcpy(cross_written, begin_marker, sizeof(begin_marker) - 1U);
    memcpy(cross_written + CROSS_SIZE - (sizeof(end_marker) - 1U),
           end_marker, sizeof(end_marker) - 1U);
    memcpy(cross_written + CROSS_SIZE, append_marker, APPEND_SIZE);

    fp = fopen("syslib.txt", "w");
    check(fp != NULL, "open cross-sector file");
    if (fp != NULL) {
        check(fwrite(cross_written, 1U, CROSS_SIZE, fp) == CROSS_SIZE,
              "cross-sector write count");
        check(ftell(fp) == (long)CROSS_SIZE, "cross-sector write position");
        check(fclose(fp) == 0, "cross-sector close");
    }

    fp = fopen("syslib.txt", "r");
    check(fp != NULL, "reopen cross-sector file");
    if (fp != NULL) {
        memset(cross_read, 0, sizeof(cross_read));
        count = fread(cross_read, 1U, CROSS_SIZE, fp);
        check(count == CROSS_SIZE &&
              memcmp(cross_read, cross_written, CROSS_SIZE) == 0,
              "exact cross-sector read-back");
        check(fread(buffer, 1U, 1U, fp) == 0U && feof(fp) != 0 &&
              ferror(fp) == 0, "cross-sector EOF state");
        check(fclose(fp) == 0, "cross-sector read close");
    }

    fp = fopen("syslib.txt", "a");
    check(fp != NULL, "open cross-sector append");
    if (fp != NULL) {
        check(ftell(fp) == (long)CROSS_SIZE, "append begins at EOF");
        check(fwrite(append_marker, 1U, APPEND_SIZE, fp) == APPEND_SIZE,
              "cross-sector append count");
        check(fclose(fp) == 0, "append close");
    }

    fp = fopen("syslib.txt", "r");
    check(fp != NULL, "reopen appended file");
    if (fp != NULL) {
        memset(cross_read, 0, sizeof(cross_read));
        count = fread(cross_read, 1U, CROSS_SIZE + APPEND_SIZE, fp);
        check(count == CROSS_SIZE + APPEND_SIZE &&
              memcmp(cross_read, cross_written,
                     CROSS_SIZE + APPEND_SIZE) == 0,
              "append preserves all exact bytes");
        check(fclose(fp) == 0, "appended read close");
    }

    check(write(1, "", 0) == 0, "console write count");
    check(call_unknown_syscall() == -1, "unknown syscall rejected");

    if (failures == 0) {
        puts("SYSCALL/STREAM TESTS PASSED");
        return 0;
    }
    printf("SYSCALL/STREAM FAILURES: %d\n", failures);
    return 1;
}
