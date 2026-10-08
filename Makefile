CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -std=c11

bin/omarchy-k380-fnlock: helper/omarchy-k380-fnlock.c
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f bin/omarchy-k380-fnlock

.PHONY: clean
