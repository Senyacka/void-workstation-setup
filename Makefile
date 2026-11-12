# Проверки качества репозитория. Установку не запускают.
SHELL := /bin/sh
SH_FILES := $(wildcard *.sh tools/*.sh lib/*.sh lang/*.sh)

.PHONY: check syntax shellcheck packages desc privacy clean

check: syntax packages desc privacy

syntax:
	@for f in $(SH_FILES); do sh -n "$$f" || exit 1; done
	@python3 -c "import sys; [compile(open(f).read(), f, 'exec') for f in sys.argv[1:]]" tools/pkgdiff.py
	@echo 'syntax: ок'

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
	     shellcheck -S warning $(SH_FILES) || exit 1; \
	 else echo 'shellcheck не установлен - пропущено'; fi

packages:
	@./tools/check-packages.sh

desc:
	@./tools/check-desc.sh

privacy:
	@./tools/privacy-scan.sh

clean:
	@rm -rf state .collect
