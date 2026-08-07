#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_ROWS 21
#define MAX_COLS 78
#define CONTENT_COLS (MAX_COLS - 1)
#define SCREEN_COLS 78

static char text_buffer[MAX_ROWS][MAX_COLS];
static int line_lengths[MAX_ROWS];
static int cur_row = 0;
static int cur_col = 0;
static int num_rows = 1;
static char filename[64] = "001.txt";
static int is_modified = 0;
static int ctrl_c_confirm = 0;
static int load_rejected = 0;
static char notice[79];

static void set_notice(const char *message) {
    strncpy(notice, message, sizeof(notice) - 1);
    notice[sizeof(notice) - 1] = '\0';
}

static void clear_document(void) {
    int r;

    for (r = 0; r < MAX_ROWS; r++) {
        line_lengths[r] = 0;
        memset(text_buffer[r], 0, MAX_COLS);
    }
    cur_row = 0;
    cur_col = 0;
    num_rows = 1;
    is_modified = 0;
}

static void pad_spaces(int count) {
    while (count-- > 0) {
        putchar(' ');
    }
}

static void render_editor(void) {
    int r, c, written;
    char status[79];

    /* 1. Header Bar (Row 0) */
    set_cursor(0, 0);
    printf("==================== [ VEDIT - MINI-OS Text Editor ] ====================");

    /* 2. Text Content (Rows 1..21) */
    for (r = 0; r < MAX_ROWS; r++) {
        set_cursor(r + 1, 0);
        written = 0;
        if (r < num_rows) {
            for (c = 0; c < line_lengths[r] && c < MAX_COLS; c++) {
                putchar(text_buffer[r][c]);
                written++;
            }
        }
        /* Pad remaining columns with spaces up to col 78 so VGA cursor doesn't wrap to line 25 */
        if (written < SCREEN_COLS) {
            pad_spaces(SCREEN_COLS - written);
        }
    }

    /* 3. Status Bar (Row 22) */
    set_cursor(22, 0);
    snprintf(status, sizeof(status),
             "--- File: %s %s | Line: %d/%d | Col: %d ---",
             filename,
             is_modified ? "[Modified]" : "[Saved]",
             cur_row + 1,
             num_rows,
             cur_col + 1);
    written = printf("%s", status);
    if (written < SCREEN_COLS) {
        pad_spaces(SCREEN_COLS - written);
    }

    /* 4. Controls Line (Row 23) */
    set_cursor(23, 0);
    if (notice[0] != '\0') {
        written = printf("%s", notice);
    } else if (ctrl_c_confirm) {
        written = printf("WARNING: Unsaved changes! Press Ctrl+C again to FORCE QUIT.");
    } else {
        written = printf("[Ctrl+S: Save] [Ctrl+C / Ctrl+Q / ESC: Quit] [Arrow Keys: Move]");
    }
    if (written < SCREEN_COLS) {
        pad_spaces(SCREEN_COLS - written);
    }

    /* Position hardware VGA cursor ONCE at current active editing position */
    move_cursor(cur_row + 1, cur_col);
}


static void save_to_file(void) {
    FILE *fp;
    int r;
    int failed;

    if (load_rejected) {
        set_notice("ERROR: original file was not loaded; save is blocked.");
        return;
    }

    fp = fopen(filename, "w");

    if (!fp) {
        set_notice("ERROR: unable to open the file for writing.");
        return;
    }

    failed = 0;
    for (r = 0; r < num_rows; r++) {
        if (line_lengths[r] > 0) {
            if (fwrite(text_buffer[r], 1, line_lengths[r], fp) !=
                (size_t)line_lengths[r]) {
                failed = 1;
                break;
            }
        }
        if (r < num_rows - 1) {
            if (fwrite("\n", 1, 1, fp) != 1) {
                failed = 1;
                break;
            }
        }
    }

    if (!failed && fflush(fp) != 0) {
        failed = 1;
    }
    if (fclose(fp) != 0) {
        failed = 1;
    }
    if (failed) {
        set_notice("ERROR: the file could not be saved completely.");
        return;
    }

    is_modified = 0;
    ctrl_c_confirm = 0;
    set_notice("SUCCESS: file saved.");
}

static void load_file_if_exists(void) {
    FILE *fp;
    char ch;
    int row;
    int col;
    int invalid;

    fp = fopen(filename, "r");
    clear_document();
    load_rejected = 0;

    if (!fp) {
        return;
    }

    row = 0;
    col = 0;
    invalid = 0;
    while (fread(&ch, 1, 1, fp) == 1) {
        if (ch == '\r') {
            continue;
        }
        if (ch == '\n') {
            if (row >= MAX_ROWS - 1) {
                if (fread(&ch, 1, 1, fp) == 1 || ferror(fp)) {
                    invalid = 1;
                }
                break;
            }
            row++;
            col = 0;
            num_rows = row + 1;
            continue;
        }
        if (col >= CONTENT_COLS) {
            invalid = 1;
            break;
        }
        text_buffer[row][col] = ch;
        col++;
        line_lengths[row] = col;
    }

    if (ferror(fp)) {
        invalid = 1;
    }
    fclose(fp);
    if (invalid) {
        clear_document();
        load_rejected = 1;
        set_notice("ERROR: file exceeds the 21-row by 77-column editor format.");
    }
}

static int run_render_test(void) {
    volatile unsigned char *vga;
    int failed;
    int i;

    vga = (volatile unsigned char *)0xB8000;
    clear_document();
    strcpy(filename, "render.txt");
    strcpy(text_buffer[0], "alpha");
    strcpy(text_buffer[1], "beta");
    line_lengths[0] = 5;
    line_lengths[1] = 4;
    num_rows = 2;
    cur_row = 1;
    cur_col = 2;
    is_modified = 1;
    set_notice("RENDER TEST");

    save_screen();
    clear_screen();
    render_editor();

    failed = 0;
    if (get_cursor_position() != 2 * 80 + 2) {
        failed = 1;
    }
    if (vga[(1 * 80 + 0) * 2] != 'a' ||
        vga[(1 * 80 + 4) * 2] != 'a' ||
        vga[(2 * 80 + 0) * 2] != 'b' ||
        vga[(2 * 80 + 3) * 2] != 'a') {
        failed = 1;
    }
    for (i = 5; i < SCREEN_COLS; i++) {
        if (vga[(1 * 80 + i) * 2] != ' ') {
            failed = 1;
        }
    }
    if (memcmp((const void *)(vga + (23 * 80) * 2),
               "R\017E\017N\017D\017E\017R\017 \017T\017E\017S\017T\017", 22) != 0) {
        failed = 1;
    }
    for (i = 0; i < SCREEN_COLS; i++) {
        if (vga[(24 * 80 + i) * 2] != ' ') {
            failed = 1;
        }
    }

    restore_screen();
    if (failed) {
        puts("vedit render test: FAIL");
        return 1;
    }
    puts("vedit render test: PASS");
    return 0;
}

int main(int argc, char **argv) {
    int key;
    int i;
    int prev_row;
    int prev_len;
    int curr_len;
    int split_len;

    /* Initialize buffer cleanly */
    for (i = 0; i < MAX_ROWS; i++) {
        line_lengths[i] = 0;
        memset(text_buffer[i], 0, MAX_COLS);
    }
    notice[0] = '\0';

    if (argc > 1 && argv && argv[1] &&
        (strcmp(argv[1], "--render-test") == 0 ||
         strcmp(argv[1], "test") == 0)) {
        return run_render_test();
    }


    if (argc > 1 && argv && argv[1] && argv[1][0] != '\0') {
        strncpy(filename, argv[1], sizeof(filename) - 1);
        filename[sizeof(filename) - 1] = '\0';
    } else {
        strcpy(filename, "001.txt");
    }

    load_file_if_exists();

    /* Save shell terminal screen before entering editor UI */
    save_screen();

    /* Clear screen once on editor entry */
    clear_screen();

    while (1) {
        render_editor();
        key = getchar();

        if (key <= 0) continue;

        notice[0] = '\0';

        /* Reset Ctrl+C confirm if another key is pressed */
        if (key != 3 && ctrl_c_confirm) {
            ctrl_c_confirm = 0;
        }

        /* 1. Quit Handling: Esc (27) or Ctrl+Q (17) or Ctrl+C (3) */
        if (key == 27 || key == 17 || key == 3) {
            if (!is_modified) {
                restore_screen();
                break;
            } else {
                if (key == 3) {
                    if (ctrl_c_confirm) {
                        restore_screen();
                        break;
                    } else {
                        ctrl_c_confirm = 1;
                        continue;
                    }
                } else {
                    ctrl_c_confirm = 1;
                    continue;
                }
            }
        }



        /* 2. Save Handling: Ctrl+S (19) */
        if (key == 19) {
            save_to_file();
            continue;
        }

        /* 3. Arrow Keys Movement */
        if (key == 11) { /* Up Arrow */
            if (cur_row > 0) {
                cur_row--;
                if (cur_col > line_lengths[cur_row]) {
                    cur_col = line_lengths[cur_row];
                }
            }
            continue;
        }
        if (key == 12) { /* Down Arrow */
            if (cur_row < num_rows - 1) {
                cur_row++;
                if (cur_col > line_lengths[cur_row]) {
                    cur_col = line_lengths[cur_row];
                }
            }
            continue;
        }
        if (key == 14) { /* Left Arrow */
            if (cur_col > 0) {
                cur_col--;
            } else if (cur_row > 0) {
                cur_row--;
                cur_col = line_lengths[cur_row];
            }
            continue;
        }
        if (key == 15) { /* Right Arrow */
            if (cur_col < line_lengths[cur_row]) {
                cur_col++;
            } else if (cur_row < num_rows - 1) {
                cur_row++;
                cur_col = 0;
            }
            continue;
        }

        /* 4. Backspace (8) or Delete (127 / 8) */
        if (key == 8 || key == 127) {
            if (cur_col > 0) {
                /* Remove character before cursor */
                for (i = cur_col - 1; i < line_lengths[cur_row] - 1; i++) {
                    text_buffer[cur_row][i] = text_buffer[cur_row][i + 1];
                }
                text_buffer[cur_row][line_lengths[cur_row] - 1] = 0;
                line_lengths[cur_row]--;
                cur_col--;
                is_modified = 1;
            } else if (cur_row > 0) {
                /* Merge current line onto end of previous line and shift lower lines up */
                prev_row = cur_row - 1;
                prev_len = line_lengths[prev_row];
                curr_len = line_lengths[cur_row];

                if (prev_len + curr_len < MAX_COLS) {
                    memcpy(text_buffer[prev_row] + prev_len, text_buffer[cur_row], curr_len);
                    line_lengths[prev_row] += curr_len;
                    text_buffer[prev_row][line_lengths[prev_row]] = 0;

                    for (i = cur_row; i < num_rows - 1; i++) {
                        memcpy(text_buffer[i], text_buffer[i + 1], MAX_COLS);
                        line_lengths[i] = line_lengths[i + 1];
                    }
                    memset(text_buffer[num_rows - 1], 0, MAX_COLS);
                    line_lengths[num_rows - 1] = 0;
                    
                    num_rows--;
                    if (num_rows == 0) num_rows = 1;

                    cur_row = prev_row;
                    cur_col = prev_len;
                    is_modified = 1;
                } else {
                    set_notice("LIMIT: joined line would exceed 77 columns.");
                }
            }
            continue;
        }


        /* 5. Enter / Return (13 / 10) -> New line */
        if (key == 13 || key == 10) {
            if (num_rows < MAX_ROWS) {
                /* Move lines below down by 1 row */
                for (i = num_rows; i > cur_row; i--) {
                    memcpy(text_buffer[i], text_buffer[i - 1], MAX_COLS);
                    line_lengths[i] = line_lengths[i - 1];
                }
                
                split_len = line_lengths[cur_row] - cur_col;
                
                /* cur_row+1 keeps the right part */
                memmove(text_buffer[cur_row + 1], text_buffer[cur_row + 1] + cur_col, split_len);
                line_lengths[cur_row + 1] = split_len;
                memset(text_buffer[cur_row + 1] + split_len, 0, MAX_COLS - split_len);
                
                /* cur_row keeps the left part */
                line_lengths[cur_row] = cur_col;
                memset(text_buffer[cur_row] + cur_col, 0, MAX_COLS - cur_col);
                
                cur_row++;
                num_rows++;
                cur_col = 0;
                is_modified = 1;
            } else {
                set_notice("LIMIT: editor holds at most 21 rows.");
            }
            continue;
        }

        /* 6. Printable ASCII characters */
        if (key >= 32 && key <= 126) {
            if (line_lengths[cur_row] < MAX_COLS - 1) {
                /* Insert character at cur_col */
                for (i = line_lengths[cur_row]; i > cur_col; i--) {
                    text_buffer[cur_row][i] = text_buffer[cur_row][i - 1];
                }
                text_buffer[cur_row][cur_col] = (char)key;
                cur_col++;
                line_lengths[cur_row]++;
                is_modified = 1;
            } else {
                set_notice("LIMIT: each row holds at most 77 characters.");
            }
        }
    }

    return 0;
}
