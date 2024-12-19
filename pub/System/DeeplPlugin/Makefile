FOSWIKI_ROOT?=~/foswiki/core
TARGET=build/pkg.js

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

PKG_SOURCE=\
	src/deepl.js \
	src/deeplTranslatable.js \
	src/deeplDocument.js

build/pkg.js: $(PKG_SOURCE)
	@echo creating $@; $(JSMIN) $^ > $@

clean:
	rm -f build/*

