#include "minilibc.h"
#include <stdarg.h>

void exit(int status) {
    __asm__ __volatile__ (
        "movl %0, %%ebx\n\t"
        "movl $1, %%eax\n\t"
        "int $0x80\n\t"
        :
        : "g"(status)
        : "eax", "ebx"
    );
}

int write(int fd, const char *buf, unsigned int count) {
    int ret;
    __asm__ __volatile__ (
        "movl %1, %%eax\n\t"
        "movl %2, %%ebx\n\t"
        "movl %3, %%ecx\n\t"
        "movl %4, %%edx\n\t"
        "int $0x80\n\t"
        : "=a"(ret)
        : "i"(4), "g"(fd), "g"(buf), "g"(count)
        : "ebx", "ecx", "edx"
    );
    return ret;
}

int read(int fd, char *buf, unsigned int count) {
    int ret;
    __asm__ __volatile__ (
        "movl %1, %%eax\n\t"
        "movl %2, %%ebx\n\t"
        "movl %3, %%ecx\n\t"
        "movl %4, %%edx\n\t"
        "int $0x80\n\t"
        : "=a"(ret)
        : "i"(3), "g"(fd), "g"(buf), "g"(count)
        : "ebx", "ecx", "edx"
    );
    return ret;
}

int getchar(void) {
    char c = 0;
    if (read(0, &c, 1) > 0) {
        return (unsigned char)c;
    }
    return -1;
}

char *gets(char *buf) {
    if (read(0, buf, 128) >= 0) {
        return buf;
    }
    return 0;
}


static unsigned int strlen(const char *s) {
    unsigned int len = 0;
    while (s[len]) len++;
    return len;
}

int puts(const char *str) {
    int len = strlen(str);
    write(1, str, len);
    write(1, "\n", 1);
    return len + 1;
}

static void itoa_dec(int val, char *buf) {
    char tmp[16];
    int i = 0, j = 0;
    unsigned int uval;

    if (val < 0) {
        buf[j++] = '-';
        uval = (unsigned int)(-val);
    } else {
        uval = (unsigned int)val;
    }

    if (uval == 0) {
        buf[j++] = '0';
        buf[j] = '\0';
        return;
    }

    while (uval > 0) {
        tmp[i++] = '0' + (uval % 10);
        uval /= 10;
    }

    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}

static void itoa_hex(unsigned int val, char *buf) {
    char tmp[16];
    int i = 0, j = 0;
    const char *hexchars = "0123456789abcdef";

    if (val == 0) {
        buf[j++] = '0';
        buf[j] = '\0';
        return;
    }

    while (val > 0) {
        tmp[i++] = hexchars[val % 16];
        val /= 16;
    }

    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}

int printf(const char *fmt, ...) {
    va_list args;
    const char *p;
    char numbuf[32];

    va_start(args, fmt);

    for (p = fmt; *p != '\0'; p++) {
        if (*p != '%') {
            write(1, p, 1);
            continue;
        }

        p++; // Skip '%'
        switch (*p) {
            case 'c': {
                char c = (char)va_arg(args, int);
                write(1, &c, 1);
                break;
            }
            case 's': {
                char *s = va_arg(args, char *);
                if (!s) s = "(null)";
                write(1, s, strlen(s));
                break;
            }
            case 'd': {
                int d = va_arg(args, int);
                itoa_dec(d, numbuf);
                write(1, numbuf, strlen(numbuf));
                break;
            }
            case 'x': {
                unsigned int x = va_arg(args, unsigned int);
                itoa_hex(x, numbuf);
                write(1, numbuf, strlen(numbuf));
                break;
            }
            case '%': {
                write(1, "%", 1);
                break;
            }
            default:
                write(1, "%", 1);
                write(1, p, 1);
                break;
        }
    }

    va_end(args);
    return 0;
}
