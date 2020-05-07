src = $(wildcard src/*.c)
obj = $(src:.c=.o)

CFLAGS= -O3 -march=native -flto -mtune=native
# CFLAGS = -flto -DNDEBUG -ggdb -fno-inline-functions
LFLAGS = -L/usr/local/lib/ -lfa
DEBUG = -DDEBUG
STATS = -DSTATS
PLOT = -DPLOT

CC = gcc-8

zearch: $(obj)
	$(CC) -o $@ $(CFLAGS) $^ $(LFLAGS)

debug: $(src)
	$(CC) -o $@ $(CFLAGS) $(DEBUG) $^ $(LFLAGS)

stats: $(src)
	$(CC) -o $@ $(CFLAGS) $(STATS) $^ $(LFLAGS)

plot: $(src)
	$(CC) -o $@ $(CFLAGS) $(PLOT) $^ $(LFLAGS)

.PHONY: clean
clean:
	rm -f $(obj) zearch debug stats plot
