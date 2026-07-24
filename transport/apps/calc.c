#include "minilibc.h"

/* Helper: skip whitespace */
static const char *skip_spaces(const char *p) {
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    return p;
}

/* Helper: parse positive or negative decimal integer */
static const char *parse_int(const char *p, int *val) {
    int result = 0;
    int sign = 1;
    
    p = skip_spaces(p);
    if (*p == '-') {
        sign = -1;
        p++;
    } else if (*p == '+') {
        p++;
    }

    if (*p < '0' || *p > '9') {
        *val = 0;
        return p;
    }

    while (*p >= '0' && *p <= '9') {
        result = result * 10 + (*p - '0');
        p++;
    }

    *val = result * sign;
    return p;
}

int main(void) {
    char input[64];
    const char *p;
    int num1, num2, result;
    char op;

    puts("==========================================");
    puts("   MINI-OS Interactive C90 Calculator");
    puts("==========================================");
    puts("Format: <num1> <op> <num2> (e.g. 12 + 34, 100 / 5)");
    puts("Operators: +, -, *, /  (Type 'q' to quit)\n");

    while (1) {
        printf("calc> ");
        if (!gets(input)) {
            break;
        }

        p = skip_spaces(input);

        /* Exit condition */
        if (*p == 'q' || *p == 'Q' || *p == '\0') {
            puts("Calculator exiting...");
            break;
        }

        /* Parse first number */
        p = parse_int(p, &num1);
        p = skip_spaces(p);

        /* Parse operator */
        op = *p;
        if (op != '+' && op != '-' && op != '*' && op != '/') {
            printf("Invalid operator '%c'. Use +, -, *, /\n\n", op);
            continue;
        }
        p++; /* Skip operator */

        /* Parse second number */
        p = parse_int(p, &num2);

        /* Calculate and output result */
        switch (op) {
            case '+':
                result = num1 + num2;
                printf("Result: %d + %d = %d\n\n", num1, num2, result);
                break;
            case '-':
                result = num1 - num2;
                printf("Result: %d - %d = %d\n\n", num1, num2, result);
                break;
            case '*':
                result = num1 * num2;
                printf("Result: %d * %d = %d\n\n", num1, num2, result);
                break;
            case '/':
                if (num2 == 0) {
                    puts("Error: Division by zero!\n");
                } else {
                    result = num1 / num2;
                    printf("Result: %d / %d = %d (remainder %d)\n\n", num1, num2, result, num1 % num2);
                }
                break;
        }
    }

    return 0;
}
