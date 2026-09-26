# Tractor Farm: one game of the couch-coop monorepo. Godot, GUT and the Python
# venv are shared at the repo root (make setup there).
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SHOT_SECONDS  ?= 8
SHOT_SCREEN   ?= level
SHOT_FPS      ?= 30
# Every screen `make shots` captures, and how long (level: the plan's 60 s).
SHOT_LIST     := join:8 select:6 level:60 finale:22 party:12 crops:2

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: sprites help setup setup-export ensure-import start play demo editor import test sfx assets shot shots contact export-linux clean

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
ensure-import: ## Import once if the cache is missing (fresh clone); run/test targets depend on it
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the project (needed after new audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = tractor, arrows+Enter = seeds, Space/any other key = rain cloud. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ensure-import ## Watch it play itself (SHOT_SCREEN=join|select|level|finale|party|crops)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ensure-import ## Run the GUT test suite headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sfx: ## Synthesize the sound effects and both music loops into game/audio (prints the level report)
	@uv run --quiet python tools/sfx.py

assets: sfx import ## Rebuild all generated assets (the art is drawn in code at run time)

shot: ensure-import ## Capture SHOT_SECONDS of SHOT_SCREEN in demo mode -> shots/<screen>/sheet.png
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 1280x720 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps $(SHOT_FPS) --quit-after $$(( $(SHOT_SECONDS) * $(SHOT_FPS) )) \
		-- --demo=$(SHOT_SCREEN) --mute > shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --scale 1 --cols 2
	@grep -E "SCRIPT ERROR|ERROR" shots/$(SHOT_SCREEN)/log.txt | grep -v "resources still in use at exit\|ObjectDB instances leaked" || echo -e "$(G)no errors in shots/$(SHOT_SCREEN)/log.txt$(R)"
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen (join select level finale party crops)
	@for s in $(SHOT_LIST); do $(MAKE) --no-print-directory shot SHOT_SCREEN=$${s%%:*} SHOT_SECONDS=$${s##*:} \
		SHOT_FPS=$$( [ $${s##*:} -gt 20 ] && echo 10 || echo 30 ); done

sprites: contact ## The art is drawn in code at run time: this renders its contact sheet

contact: ## Capture the crop and prop contact sheet (shots/crops/last.png is the full-size frame)
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=crops SHOT_SECONDS=2

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/tractor-farm.x86_64
	@echo -e "$(G)build/tractor-farm.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build
