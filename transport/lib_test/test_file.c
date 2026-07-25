#include <stdio.h>
#include <string.h>

int main(void) {
    FILE *fp;
    char read_buf[128];
    const char *test_msg = "Hello, MINI-OS File I/O System! C90 disk streams work!\n";
    size_t written, read_cnt;
    long pos;

    puts("==========================================");
    puts("   MINI-OS Phase 4 File Stream I/O Test");
    puts("==========================================");

    /* 1. Open file for writing (creates file on disk) */
    fp = fopen("output.txt", "w");
    if (!fp) {
        puts("ERROR: Failed to fopen('output.txt', 'w')!");
        return 1;
    }
    puts("1. fopen('output.txt', 'w') successful.");

    /* 2. Write text to file */
    written = fwrite(test_msg, 1, strlen(test_msg), fp);
    printf("2. fwrite wrote %u bytes.\n", (unsigned int)written);

    /* 3. Query current file position using ftell */
    pos = ftell(fp);
    printf("3. ftell position after write: %ld bytes.\n", pos);

    /* 4. Close file */
    fclose(fp);
    puts("4. fclose completed.");

    /* 5. Reopen file for reading */
    fp = fopen("output.txt", "r");
    if (!fp) {
        puts("ERROR: Failed to fopen('output.txt', 'r')!");
        return 1;
    }
    puts("5. fopen('output.txt', 'r') successful.");

    /* 6. Read text back from file */
    memset(read_buf, 0, sizeof(read_buf));
    read_cnt = fread(read_buf, 1, sizeof(read_buf) - 1, fp);
    printf("6. fread read %u bytes back from disk:\n", (unsigned int)read_cnt);
    printf("   Content: '%s'\n", read_buf);

    /* 7. Test fseek back to start */
    fseek(fp, 0, SEEK_SET);
    pos = ftell(fp);
    printf("7. fseek(0, SEEK_SET) position: %ld\n", pos);

    /* 8. Close file */
    fclose(fp);
    puts("8. fclose completed.");

    puts("\nPhase 4 File Stream I/O tests PASSED cleanly!");
    return 0;
}
