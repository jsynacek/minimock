PREFIX ?= /usr/local

all:
	@echo "Type 'make install' to install the script, or 'make uninstall' to uninstall it."

install: all
	@echo installing minimock to $(DESTDIR)$(PREFIX)/bin/minimock
	@mkdir -p $(DESTDIR)$(PREFIX)/bin
	@cp -f minimock.sh $(DESTDIR)$(PREFIX)/bin/minimock
	@chmod u=rwx,g=rx,o=rx $(DESTDIR)$(PREFIX)/bin/minimock

uninstall:
	@echo uninstalling $(DESTDIR)$(PREFIX)/bin/minimock
	@rm -f $(DESTDIR)$(PREFIX)/bin/minimock
