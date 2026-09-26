# Garage Band: one game of the couch-coop monorepo. Godot, GUT and the Python
# venv are shared at the repo root (make setup there).
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SHOT_SECONDS  ?= 10
SHOT_SCREEN   ?= play
SCREENS       := join select play party

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export ensure-import start play demo editor import test sfx riders assets audio-check shot shots export-linux clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-14s$(R) %s\n", $$1, $$2}'

setup: ## Shared Godot + venv (repo root), then GUT and an import for this game
	@$(MAKE) --no-print-directory -C $(ROOT) setup-tools
	@if [ ! -d $(GAME)/addons/gut ]; then \
		echo -e "$(C)GUT $(GUT_VERSION) -> $(GAME)/addons/gut$(R)"; \
		curl -sSLo /tmp/gut-$$$$.zip https://github.com/bitwes/Gut/archive/refs/tags/v$(GUT_VERSION).zip && \
		unzip -qo /tmp/gut-$$$$.zip -d /tmp/gut-$$$$ && mkdir -p $(GAME)/addons && cp -r /tmp/gut-$$$$/Gut-$(GUT_VERSION)/addons/gut $(GAME)/addons/ && \
		command rm -rf /tmp/gut-$$$$.zip /tmp/gut-$$$$; fi
	@$(MAKE) --no-print-directory import
	@echo -e "$(G)Ready. make start$(R)"

# A fresh clone (or a wiped game/.godot) has no import cache: GUT's class_names
# are unknown until Godot has scanned the project once.
ensure-import:
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the project (needed after new art/audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = Lead, arrows+Enter = Drummer, Space/any other key = Crasher. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ensure-import ## Watch the band play itself (SHOT_SCREEN=join|select|play|party)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ensure-import ## Run the GUT test suite headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sfx: ## Synthesize the drum kit one-shots and the menu sounds into game/audio (loudness report)
	@uv run --quiet python tools/sfx.py

riders: ## Refresh the rider PNGs from PixelPals (the reused 16x16 cast)
	@for r in penguin monkey fox frog robot; do command cp -f ../pixelpals/game/art/$$r.png $(GAME)/art/; done
	@command cp -f ../pixelpals/game/private_pack/art/*.png ../pixelpals/game/private_pack/art/manifest.json $(GAME)/private_pack/art/
	@command cp -f ../pixelpals/game/private_pack/riders.json $(GAME)/private_pack/
	@echo -e "$(G)riders copied$(R)"

assets: sfx import ## Rebuild the generated audio (the art is drawn in code)

audio-check: ensure-import ## Render the play demo's synth output to shots/play/audio.wav and measure it
	@mkdir -p shots/play/audio_check
	@$(GODOT) --headless --path $(GAME) -s tools/render_demo.gd -- --out=$(CURDIR)/shots/play/audio.wav 2>&1 | grep -v "^Godot Engine" || true
	@uv run --quiet python tools/sfx.py --measure shots/play/audio.wav --check shots/play/audio_check --no-write

shot: ensure-import ## Capture frames of SHOT_SCREEN (join|select|play|party) in demo mode -> shots/
	@command rm -rf shots/$(SHOT_SCREEN)/f*.png && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 640x360 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_SCREEN) --mute > shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --scale 1
	@grep -E "SCRIPT ERROR|^ERROR" shots/$(SHOT_SCREEN)/log.txt | grep -v "resources still in use at exit" || echo -e "$(G)no errors in the log$(R)"
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=join SHOT_SECONDS=8
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=select SHOT_SECONDS=11
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=play SHOT_SECONDS=14
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=party SHOT_SECONDS=10

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/garage-band.x86_64
	@echo -e "$(G)build/garage-band.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build
