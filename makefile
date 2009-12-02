equinox.so: equinox.o
	gcc -shared $< -o $@ `pkg-config --libs libxml-2.0`

clean:
	-rm equinox.so equinox.c equinox.o

%.c: %.pyx
	cython $<

%.o: CC = gcc
%.o: CFLAGS = -fPIC `python-config --cflags` \
	            `pkg-config --cflags libxml-2.0`
