test: equinox.so tests/*.py
	export PYTHONPATH="${PWD}:${PYTHONPATH}" ; \
		for I in tests/*.py; do python $${I}; done

daily: DATE=$(shell date -u +%d%b%Y)
daily: TARBALL=equinox-$(DATE).tar
daily: PREFIX=equinox-$(DATE)/
daily: test
	git archive --format=tar --prefix=$(PREFIX) -o $(TARBALL) HEAD
	gzip -9 $(TARBALL)

equinox.so: equinox.o
	gcc -shared $< -o $@ `pkg-config --libs libxml-2.0`

clean:
	-rm equinox.c *.o *.so *.pyc *.pyo

%.c: %.pyx
	cython $<

%.o: CC = gcc
%.o: CFLAGS = -fPIC `python-config --cflags` \
	            `pkg-config --cflags libxml-2.0`
