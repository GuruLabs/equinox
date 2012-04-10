test: equinox.so test-selector test-unescape
	./test-selector
	./test-unescape
	@echo
	export PYTHONPATH="${PWD}:${PYTHONPATH}" ; \
		for I in tests/*.py; do python $${I}; done

clean:
	-rm equinox.c test-* *.o *.so *.pyc *.pyo

daily: DATE=$(shell date -u +%d%b%Y)
daily: TARBALL=equinox-$(DATE).tar
daily: PREFIX=equinox-$(DATE)/
daily: test
	git archive --format=tar --prefix=$(PREFIX) -o $(TARBALL) HEAD
	gzip -9 $(TARBALL)

equinox.so: equinox.o
	gcc -shared $< -o $@ `pkg-config --libs libxml-2.0`

test-selector: selector.c
	gcc -o $@ -std=c99 -DTEST -lcheck $^

test-unescape: unescape.c
	gcc -o $@ -std=c99 -DTEST -lcheck $^

%.c: %.pyx
	cython $<

%.o: CC = gcc
%.o: CFLAGS = -fPIC `python-config --cflags` \
	            `pkg-config --cflags libxml-2.0`
