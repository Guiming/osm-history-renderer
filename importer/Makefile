#------------------------------------------------------------------------------
#
#  osm history importer makefile
#
#------------------------------------------------------------------------------

CXX ?= c++
PKG_CONFIG ?= pkg-config
GEOS_CONFIG ?= geos-config

CPPFLAGS += $(shell $(PKG_CONFIG) --cflags libpq)
CPPFLAGS += $(shell $(GEOS_CONFIG) --cflags)
CXXFLAGS ?= -g -O3
CXXFLAGS += -std=c++17 -Wall -Wextra -Wpedantic
CXXFLAGS += $(shell getconf LFS_CFLAGS)
LDLIBS += -lexpat -lbz2
LDLIBS += $(shell $(PKG_CONFIG) --libs libpq)
LDLIBS += -lz -pthread
LDLIBS += $(shell $(GEOS_CONFIG) --clibs)

.PHONY: all clean install test test-geos

all: osm-history-importer

osm-history-importer: importer.cpp handler.hpp geombuilder.hpp geoscontext.hpp nodestore.hpp nodestore/stl.hpp nodestore/sparse.hpp polygonidentifyer.hpp zordercalculator.hpp sorttest.hpp project.hpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

test/test-geoscontext: test/test-geoscontext.cpp geoscontext.hpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

test-geos: test/test-geoscontext
	./test/test-geoscontext

test: test-geos

install:
	install -m 755 -d $(DESTDIR)/usr/bin
	install -m 755 osm-history-importer $(DESTDIR)/usr/bin/osm-history-importer
	install -m 755 -d $(DESTDIR)/usr/share/osm-history-importer/scheme
	install -m 644 scheme/*.sql $(DESTDIR)/usr/share/osm-history-importer/scheme

clean:
	rm -f *.o core osm-history-importer test/test-geoscontext

check:
	cppcheck --enable=all *.cpp

# This will try to compile each include file on its own to detect missing
# #include directives. Note that if this reports [OK], it is not enough
# to be sure it will compile in production code. But if it reports [FAILED]
# we know we are missing something.
check-includes:
	echo "check includes report:" >check-includes-report; \
	for FILE in *.hpp *.cpp; do \
		echo "$${FILE}:" >>check-includes-report; \
		echo -n "$${FILE} "; \
		if `$(CXX) $(CPPFLAGS) $(CXXFLAGS) $${FILE} 2>>check-includes-report`; then \
			echo "[OK]"; \
		else \
			echo "[FAILED]"; \
		fi; \
		rm -f $${FILE}.gch; \
	done

indent:
	astyle --style=java --indent-namespaces --indent-switches --pad-header --suffix=none --recursive include/\*.hpp examples/\*.cpp examples/\*.hpp osmjs/\*.cpp test/\*.cpp

#deb:
#	debuild -I -us -uc

#deb-clean:
#	debuild clean
