PLUGIN_ID  ?= yuler.omaports
PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
REPO       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL      := /bin/bash

.PHONY: link unlink test validate enable disable restart

# Point Omarchy at this checkout. Refuse to replace any existing path: the
# caller must remove or move it explicitly before linking this checkout.
link:
	mkdir -p "$(dir $(PLUGIN_DIR))"
	@if [[ -e "$(PLUGIN_DIR)" || -L "$(PLUGIN_DIR)" ]]; then \
	  if [[ -L "$(PLUGIN_DIR)" && "$$(readlink -f "$(PLUGIN_DIR)")" == "$(REPO)" ]]; then \
	    echo "already linked $(PLUGIN_DIR) -> $(REPO)"; \
	  else \
	    echo "refusing to replace existing path: $(PLUGIN_DIR)" >&2; \
	    echo "move it away or remove it explicitly, then run make link again" >&2; \
	    exit 1; \
	  fi; \
	else \
	  ln -s "$(REPO)" "$(PLUGIN_DIR)"; \
	fi
	@echo "linked $(PLUGIN_DIR) -> $(REPO)"
	$(MAKE) validate

unlink:
	@if [[ -L $(PLUGIN_DIR) ]]; then \
	  rm "$(PLUGIN_DIR)"; \
	  echo "removed $(PLUGIN_DIR)"; \
	elif [[ -e $(PLUGIN_DIR) ]]; then \
	  echo "refusing to remove $(PLUGIN_DIR): not a symlink" >&2; \
	  exit 1; \
	else \
	  echo "nothing to unlink"; \
	fi

test:
	node test/model-test.js

validate: test
	omarchy plugin validate "$(REPO)"

enable: link
	omarchy plugin enable "$(PLUGIN_ID)" --section right

disable:
	omarchy plugin disable "$(PLUGIN_ID)"

restart:
	omarchy restart shell
