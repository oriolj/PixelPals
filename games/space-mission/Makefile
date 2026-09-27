# One game of the couch-coop monorepo. Godot, GUT and the Python venv are
# shared at the repo root (make setup there).
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SHOT_SCREEN   ?= orbit
SHOT_SECONDS  ?= $(or $(SHOT_LEN_$(SHOT_SCREEN)),8)
# Seconds captured per screen by `make shots` (the demo mission is shortened).
SHOT_LEN_join    := 8
SHOT_LEN_select  := 7
SHOT_LEN_orbit   := 70
SHOT_LEN_landing := 22
SHOT_LEN_mars    := 60
SHOT_LEN_party   := 14
SHOT_COUNT_orbit := 12
SHOT_COUNT_mars  := 12
SHOT_COUNT_landing := 10

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export ensure-import start play demo editor import test sprites sfx assets shot shots export-linux clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-14s$(R) %s\n", $$1, $$2}'

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
ensure-import: ## Import the project once if the cache is missing (fresh clone)
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the project (needed after new art/audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = Pilot, arrows+Enter = Arm, Space/any other key = Camera. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ensure-import ## Watch it play itself (SHOT_SCREEN=join|select|orbit|landing|mars|party)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ensure-import ## Run the GUT test suite headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sprites: ## Render art_src/ grids + tools/art_gen.py to game/art PNGs, lint them, write the contact sheets
	@uv run --quiet python tools/sprites.py

sfx: ## Synthesize the sound effects and music into game/audio (prints the loudness report)
	@uv run --quiet python tools/sfx.py

assets: sprites sfx import ## Rebuild all generated art and audio

shot: ensure-import ## Capture frames of SHOT_SCREEN in demo mode -> shots/<screen>/sheet.png
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 320x180 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_SCREEN) --mute >shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --count $(or $(SHOT_COUNT_$(SHOT_SCREEN)),8)
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)  (errors: $$(grep -c 'ERROR' shots/$(SHOT_SCREEN)/log.txt))"

shots: ## Capture every screen
	@for s in join select orbit landing mars party; do $(MAKE) --no-print-directory shot SHOT_SCREEN=$$s; done

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/space-mission.x86_64
	@echo -e "$(G)build/space-mission.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build
