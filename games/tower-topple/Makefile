# Tower Topple: one game of the couch-coop monorepo. Godot, GUT and the Python
# venv are shared at the repo root (make setup there).
SHELL         := /bin/bash
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SESSION       := tower-topple
SHOT_SCREEN   ?= play
# The play capture holds two build phases and two topples (demo towers are short).
ifeq ($(SHOT_SCREEN),play)
SHOT_SECONDS  ?= 40
SHOT_COUNT    ?= 12
else
SHOT_SECONDS  ?= 8
SHOT_COUNT    ?= 8
endif

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export ensure-import import start play demo editor test sprites sfx assets shot shots export-linux clean tmux tmux-d tmux-n tmux-new-session

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-16s$(R) %s\n", $$1, $$2}'

setup: ## Shared Godot + venv (repo root), then GUT and an import for this game
	@$(MAKE) --no-print-directory -C $(ROOT) setup-tools
	@if [ ! -d $(GAME)/addons/gut ]; then \
		echo -e "$(C)GUT $(GUT_VERSION) -> $(GAME)/addons/gut$(R)"; \
		curl -sSLo /tmp/gut-$$$$.zip https://github.com/bitwes/Gut/archive/refs/tags/v$(GUT_VERSION).zip && \
		unzip -qo /tmp/gut-$$$$.zip -d /tmp/gut-$$$$ && mkdir -p $(GAME)/addons && command cp -r /tmp/gut-$$$$/Gut-$(GUT_VERSION)/addons/gut $(GAME)/addons/ && \
		command rm -rf /tmp/gut-$$$$.zip /tmp/gut-$$$$; fi
	@$(MAKE) --no-print-directory import
	@echo -e "$(G)Ready. make start$(R)"

# A fresh clone (or a wiped game/.godot) has no import cache: GUT's class_names
# are unknown until Godot has scanned the project once.
ensure-import: ## Import the project only when the cache is missing (fresh clone)
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the project (needed after new art/audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = Builder, arrows+Enter = Dropper, Space/any other key = Toppler. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ensure-import ## Run the game on scripted input (SHOT_SCREEN=join|select|play|party)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

# GUT only warns when a test script fails to parse (and skips it): fail on that too.
test: ensure-import ## Run the GUT test suite headless (fails on any script parse error too)
	@set -o pipefail; $(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | tee /tmp/tower-topple-test-$$$$.log; \
	status=$$?; if grep -q "SCRIPT ERROR" /tmp/tower-topple-test-$$$$.log; then echo -e "\033[31mSCRIPT ERROR in the test run\033[0m"; status=1; fi; \
	command rm -f /tmp/tower-topple-test-$$$$.log; exit $$status

sprites: ## Render the rider grids (art_src/) to game/art PNGs, lint them, write the contact sheet
	@uv run --quiet python tools/sprites.py

sfx: ## Synthesize every sound and both music loops into game/audio (prints the level report)
	@uv run --quiet python tools/sfx.py

assets: sprites sfx import ## Rebuild all generated art and audio

shot: ensure-import ## Capture frames of SHOT_SCREEN (join|select|play|party) in demo mode -> shots/
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 640x360 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_SCREEN) --mute > shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@grep -E "SCRIPT ERROR|ERROR" shots/$(SHOT_SCREEN)/log.txt | grep -v "resources still in use at exit\|ObjectDB instances leaked" || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --scale 2 --count $(SHOT_COUNT)
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen
	@for s in join select play party; do $(MAKE) --no-print-directory shot SHOT_SCREEN=$$s; done

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/tower-topple.x86_64
	@echo -e "$(G)build/tower-topple.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build

tmux: ## Attach to (or create) the tower-topple tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Grouped session: shared windows, independent navigation
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)

tmux-new-session: tmux-n
