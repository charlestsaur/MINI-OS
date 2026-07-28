#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_ROWS 21
#define MAX_COLS 78

static char text_buffer[MAX_ROWS][MAX_COLS];
static int line_lengths[MAX_ROWS];
static int cur_row = 0;
static int cur_col = 0;
static int num_rows = 1;
static char filename[64] = "001.txt";
static int is_modified = 0;
static int ctrl_c_confirm = 0;

static void pad_spaces(int count) {
    while (count-- > 0) {
        putchar(' ');
    }
}

static void render_editor(void) {
    int r, c, written;

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
        if (written < 78) {
            pad_spaces(78 - written);
        }
    }

    /* 3. Status Bar (Row 22) */
    set_cursor(22, 0);
    written = printf("--- File: %s %s | Line: %d/%d | Col: %d ---", 
                     filename, 
                     is_modified ? "[Modified]" : "[Saved]", 
                     cur_row + 1, 
                     num_rows, 
                     cur_col + 1);
    if (written < 78) {
        pad_spaces(78 - written);
    }

    /* 4. Controls Line (Row 23) */
    set_cursor(23, 0);
    if (ctrl_c_confirm) {
        written = printf("WARNING: Unsaved changes! Press Ctrl+C again to FORCE QUIT.");
    } else {
        written = printf("[Ctrl+S: Save] [Ctrl+C / Ctrl+Q / ESC: Quit] [Arrow Keys: Move]");
    }
    if (written < 78) {
        pad_spaces(78 - written);
    }

    /* Position hardware VGA cursor ONCE at current active editing position */
    move_cursor(cur_row + 1, cur_col);
}


static void save_to_file(void) {
    FILE *fp = fopen(filename, "w");
    int r;

    if (!fp) {
        set_cursor(23, 0);
        printf("ERROR: Failed to save file '%s'!                          ", filename);
        return;
    }

    for (r = 0; r < num_rows; r++) {
        if (line_lengths[r] > 0) {
            fwrite(text_buffer[r], 1, line_lengths[r], fp);
        }
        if (r < num_rows - 1) {
            fwrite("\n", 1, 1, fp);
        }
    }

    fflush(fp);
    fclose(fp);
    is_modified = 0;
    ctrl_c_confirm = 0;

    set_cursor(23, 0);
    printf("SUCCESS: File '%s' saved cleanly to disk!                     ", filename);
}

static void load_file_if_exists(void) {
    FILE *fp = fopen(filename, "r");
    char line[128];
    int len, c;

    cur_row = 0;
    cur_col = 0;
    is_modified = 0;

    if (!fp) {
        num_rows = 1;
        line_lengths[0] = 0;
        memset(text_buffer[0], 0, MAX_COLS);
        return;
    }

    num_rows = 0;
    while (fgets(line, sizeof(line), fp) != NULL && num_rows < MAX_ROWS) {
        len = (int)strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        if (len > MAX_COLS - 1) len = MAX_COLS - 1;

        memset(text_buffer[num_rows], 0, MAX_COLS);
        for (c = 0; c < len; c++) {
            text_buffer[num_rows][c] = line[c];
        }
        line_lengths[num_rows] = len;
        num_rows++;
    }

    fclose(fp);
    if (num_rows == 0) num_rows = 1;
    is_modified = 0;
}

int main(int argc, char **argv) {
    int key;
    int i;

    /* Initialize buffer cleanly */
    for (i = 0; i < MAX_ROWS; i++) {
        line_lengths[i] = 0;
        memset(text_buffer[i], 0, MAX_COLS);
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
                int prev_row = cur_row - 1;
                int prev_len = line_lengths[prev_row];
                int curr_len = line_lengths[cur_row];

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
                
                int split_len = line_lengths[cur_row] - cur_col;
                
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
            }
        }
    }

    return 0;
}
