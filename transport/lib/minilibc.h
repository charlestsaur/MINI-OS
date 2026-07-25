#ifndef MINILIBC_H
#define MINILIBC_H

#ifndef NULL
#define NULL ((void *)0)
#endif

typedef unsigned int size_t;

#define stdin ((void *)0)
#define stdout ((void *)1)
#define stderr ((void *)2)

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#define EOF (-1)

typedef struct FILE FILE;

/* System & I/O Functions */
void exit(int status);
int write(int fd, const char *buf, unsigned int count);
int read(int fd, char *buf, unsigned int count);
int getchar(void);
int putchar(int c);
char *gets(char *buf);
char *fgets(char *s, int size, void *stream);
int puts(const char *str);
int printf(const char *fmt, ...);
int sprintf(char *str, const char *fmt, ...);
int snprintf(char *str, size_t size, const char *fmt, ...);
void move_cursor(int row, int col);
void set_cursor(int row, int col);
void clear_screen(void);
void save_screen(void);
void restore_screen(void);




/* File Stream I/O Functions */
FILE *fopen(const char *filename, const char *mode);
int fclose(FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int fseek(FILE *stream, long offset, int whence);
long ftell(FILE *stream);
void rewind(FILE *stream);
int fflush(FILE *stream);
int feof(FILE *stream);
int ferror(FILE *stream);



/* <string.h> Functions */
size_t strlen(const char *s);
char *strcpy(char *dest, const char *src);
char *strncpy(char *dest, const char *src, size_t n);
char *strcat(char *dest, const char *src);
char *strncat(char *dest, const char *src, size_t n);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
char *strtok(char *str, const char *delim);
void *memset(void *s, int c, size_t n);
void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
void *memchr(const void *s, int c, size_t n);

/* <ctype.h> Functions */
int isalpha(int c);
int isdigit(int c);
int isalnum(int c);
int isspace(int c);
int islower(int c);
int isupper(int c);
int isprint(int c);
int isgraph(int c);
int ispunct(int c);
int isxdigit(int c);
int iscntrl(int c);
int toupper(int c);
/* <stdlib.h> Functions */
void *malloc(size_t size);
void free(void *ptr);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
int atoi(const char *nptr);
long strtol(const char *nptr, char **endptr, int base);
unsigned long strtoul(const char *nptr, char **endptr, int base);
int abs(int j);
long labs(long j);
int rand(void);
void srand(unsigned int seed);
void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));

#endif
