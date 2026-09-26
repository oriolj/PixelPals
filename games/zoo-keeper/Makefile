# Zoo Keeper: one game of the couch-coop monorepo. Godot, GUT and the Python
# venv are shared at the repo root (make setup there).
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SESSION       := zoo-keeper
SHOT_SCREEN   ?= zoo
SHOT_FPS      ?= 15
# Seconds captured per screen (the demo driver's script for each one fits in it).
SECS_join     := 7
SECS_select   := 5
SECS_zoo      := 14
SECS_party    := 11
SECS_gallery  := 16
SHOT_SECONDS  ?= $(or $(SECS_$(SHOT_SCREEN)),8)
SCREENS       := join select zoo party gallery

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export ensure-import import start play demo editor test sfx assets gallery shot shots export-linux clean tmux tmux-d tmux-n

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

import: ## Let Godot scan and import the project (needed after new audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = keeper, arrows+Enter = feeder, Space/any other key = singer. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ensure-import ## Run the game on scripted input (SHOT_SCREEN=join plays the whole flow)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ensure-import ## Run the GUT test suite headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sfx: ## Synthesize the animal voices, sound effects and music into game/audio (prints the measurements)
	@uv run --quiet python tools/sfx.py

assets: sfx import ## Rebuild all generated audio (the art is drawn by code at run time)

gallery: ## Capture the asset gallery (every animal and prop, every pose, plus silhouettes)
	@$(MAKE) --no-print-directory shot SHOT_SCREEN=gallery

shot: ensure-import ## Capture frames of SHOT_SCREEN (join|select|zoo|party|gallery) in demo mode -> shots/
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 1280x720 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps $(SHOT_FPS) --quit-after $$(( $(SHOT_SECONDS) * $(SHOT_FPS) )) \
		-- --demo=$(SHOT_SCREEN) --mute > shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --scale 1 --count 8 --cols 2
	@if grep -E "SCRIPT ERROR|^ERROR" shots/$(SHOT_SCREEN)/log.txt >/dev/null; then \
		echo -e "$(Y)errors in shots/$(SHOT_SCREEN)/log.txt$(R)"; grep -E -A2 "SCRIPT ERROR|^ERROR" shots/$(SHOT_SCREEN)/log.txt | head -20; fi
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen
	@for s in $(SCREENS); do $(MAKE) --no-print-directory shot SHOT_SCREEN=$$s; done

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/zoo-keeper.x86_64
	@echo -e "$(G)build/zoo-keeper.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build

tmux: ## Attach to (or create) the zoo-keeper tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first (full size for this terminal)
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Attach through a grouped session (independent navigation)
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)
