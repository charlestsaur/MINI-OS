#include "minilibc.h"

int main(void) {
    char name[64];

    puts("==========================================");
    puts("  MINI-OS Interactive C90 Application");
    puts("==========================================");
    
    printf("Please enter your name: ");
    if (!gets(name)) {
        puts("No input received.");
        return 0;
    }

    printf("\nWelcome, %s! You are running C code in MINI-OS!\n", name);
    puts("Interactive session completed cleanly!");
    return 0;
}

