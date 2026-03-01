src = $(wildcard src/*.c)

# Use system gcc by default. -fcommon is required for gcc >= 10 because this
# codebase defines global variables (mem, expand) directly in header files,
# which violates the C standard's one-definition rule. gcc-8 allowed this via
# common symbols; newer compilers default to -fno-common. -flto is omitted
# because it conflicts with -fcommon.
CC ?= gcc
CFLAGS ?= -O3 -march=native -mtune=native -fcommon

# libfa ships with the augeas project.
# Ubuntu/Debian:  sudo apt-get install libaugeas-dev
# Custom build:   set LFLAGS=-L/usr/local/lib -lfa  (and update LD_LIBRARY_PATH)
LFLAGS ?= -lfa
DEBUG = -DDEBUG
STATS = -DSTATS
PLOT = -DPLOT

zearch: $(src)
	$(CC) -o $@ $(CFLAGS) $^ $(LFLAGS)

debug: $(src)
	$(CC) -o $@ $(CFLAGS) $(DEBUG) $^ $(LFLAGS)

stats: $(src)
	$(CC) -o $@ $(CFLAGS) $(STATS) $^ $(LFLAGS)

plot: $(src)
	$(CC) -o $@ $(CFLAGS) $(PLOT) $^ $(LFLAGS)

.PHONY: clean
clean:
	rm -f zearch debug stats plot
