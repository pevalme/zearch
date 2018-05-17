src = $(wildcard src/*.c)
obj = $(src:.c=.o)

CFLAGS= -O3 -march=native -flto
LFLAGS= -lfa
DEBUG = -DDEBUG
STATS = -DSTATS
PLOT = -DPLOT

CC = gcc-7

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
