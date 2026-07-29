#include <stdio.h>
#include <string.h>
#include <limits.h>

static int failures = 0;

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
        check(fseek(fp, -1, SEEK_SET) < 0, "negative seek rejected");
        check(fseek(fp, LONG_MAX, SEEK_END) < 0,
              "overflowing seek rejected");
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
    check(write(1, "", 0) == 0, "console write count");
    check(call_unknown_syscall() == -1, "unknown syscall rejected");

    if (failures == 0) {
        puts("SYSCALL/STREAM TESTS PASSED");
        return 0;
    }
    printf("SYSCALL/STREAM FAILURES: %d\n", failures);
    return 1;
}
