#ifndef MINILIBC_H
#define MINILIBC_H

void exit(int status);
int write(int fd, const char *buf, unsigned int count);
int read(int fd, char *buf, unsigned int count);
int getchar(void);
char *gets(char *buf);
int puts(const char *str);
int printf(const char *fmt, ...);

#endif

