/*
 * hyperscan.c – line-counting search using Intel Hyperscan.
 *
 * Usage:  hyperscan <regex> [file]
 *
 * Reads lines from <file> (or stdin if omitted), counts lines that contain
 * a match for <regex>, and prints the count to stdout.  Behaviour mirrors
 * `grep -c` so the benchmark scripts can use it as a drop-in baseline.
 *
 * Build:
 *   gcc -O2 -o hyperscan hyperscan.c -lhs
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hs/hs.h>

#define LINE_MAX_LEN 65536

static int had_match;

static int on_match(unsigned int id, unsigned long long from,
                    unsigned long long to, unsigned int flags, void *ctx)
{
    (void)id; (void)from; (void)to; (void)flags; (void)ctx;
    had_match = 1;
    return 1; /* non-zero stops scanning after first match */
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: hyperscan <regex> [file]\n");
        return 1;
    }

    hs_database_t    *db  = NULL;
    hs_compile_error_t *err = NULL;

    if (hs_compile(argv[1], HS_FLAG_SINGLEMATCH, HS_MODE_BLOCK,
                   NULL, &db, &err) != HS_SUCCESS) {
        fprintf(stderr, "hyperscan: compile error for '%s': %s\n",
                argv[1], err->message);
        hs_free_compile_error(err);
        return 1;
    }

    hs_scratch_t *scratch = NULL;
    if (hs_alloc_scratch(db, &scratch) != HS_SUCCESS) {
        fprintf(stderr, "hyperscan: scratch allocation failed\n");
        hs_free_database(db);
        return 1;
    }

    FILE *fp = (argc >= 3) ? fopen(argv[2], "r") : stdin;
    if (!fp) {
        perror(argv[2]);
        hs_free_scratch(scratch);
        hs_free_database(db);
        return 1;
    }

    char *line = malloc(LINE_MAX_LEN);
    if (!line) {
        fprintf(stderr, "hyperscan: malloc failed\n");
        if (fp != stdin) fclose(fp);
        hs_free_scratch(scratch);
        hs_free_database(db);
        return 1;
    }

    long count = 0;
    while (fgets(line, LINE_MAX_LEN, fp)) {
        int len = (int)strlen(line);
        if (len > 0 && line[len - 1] == '\n')
            line[--len] = '\0';
        if (len == 0)
            continue;
        had_match = 0;
        hs_scan(db, line, (unsigned int)len, 0, scratch, on_match, NULL);
        if (had_match)
            count++;
    }

    printf("%ld\n", count);

    free(line);
    if (fp != stdin) fclose(fp);
    hs_free_scratch(scratch);
    hs_free_database(db);
    return 0;
}
