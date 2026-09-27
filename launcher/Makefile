# The TV launcher of the couch-coop monorepo. Godot and the Python venv are
# shared at the repo root (make setup-tools there).
ROOT          := ..
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SHOT_SECONDS  ?= 7
SHOT_DEMO     ?= browse
SHOT_ARGS     ?=

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help ensure-import import start window test sfx icon assets shot shots launch-test clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-14s$(R) %s\n", $$1, $$2}'

# A fresh clone has no game/.godot: GUT's class_names are unknown until Godot
# has scanned the project once. (The launcher itself loads everything from bytes.)
ensure-import:
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the launcher project
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Run the launcher fullscreen (the TV)
	@echo -e "$(C)Any pad or keyboard: left/right to choose, A / Enter / Space to play. Back+Start (hold) or Ctrl+Q leaves a game.$(R)"
	@$(GODOT) --path $(GAME) --fullscreen

window: ensure-import ## Run the launcher in a window, games windowed too (development)
	@$(GODOT) --path $(GAME) --resolution 1280x720 -- --windowed-games

test: ensure-import ## Run the launcher's GUT tests headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sfx: ## Synthesize the launcher's sounds and menu loop into game/audio
	@uv run --quiet python tools/sfx.py

icon: ## Draw the launcher icon (game/icon.png, also the desktop icon)
	@uv run --quiet python tools/icon.py

assets: sfx icon ## Rebuild the generated sounds and icon

shot: ensure-import ## Capture 1080p frames under xvfb (SHOT_DEMO=browse|soon|power, SHOT_ARGS="--root=..") -> shots/<demo>/
	@command rm -rf shots/$(SHOT_DEMO) && mkdir -p shots/$(SHOT_DEMO)
	@xvfb-run -a -s "-screen 0 1920x1080x24" $(GODOT) --path $(GAME) --resolution 1920x1080 \
		--write-movie $(CURDIR)/shots/$(SHOT_DEMO)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_DEMO) --mute --prefs=$(CURDIR)/shots/prefs.cfg $(SHOT_ARGS) >/dev/null 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_DEMO) --count 4 --scale 1
	@echo -e "$(G)shots/$(SHOT_DEMO)/sheet.png$(R)"

shots: ## Capture every demo
	@for s in browse soon power; do $(MAKE) --no-print-directory shot SHOT_DEMO=$$s; done

launch-test: ensure-import ## Real launch under xvfb: start PixelPals, let it quit after 3 s, check the launcher restores
	@command rm -rf shots/launch && mkdir -p shots/launch
	@timeout 120 xvfb-run -a -s "-screen 0 1920x1080x24" $(GODOT) --path $(GAME) --resolution 1920x1080 \
		-- --autolaunch=pixelpals --game-arg=--quit-after-seconds=3 --quit-after-return=1.5 --mute \
		--prefs=$(CURDIR)/shots/launch/prefs.cfg --shot-dir=$(CURDIR)/shots/launch 2>&1 | grep '^launcher:' | tee shots/launch/log.txt
	@grep -q 'launcher: restored, selected pixelpals' shots/launch/log.txt && echo -e "$(G)launch test OK$(R)" || { echo -e "$(Y)launch test FAILED$(R)"; exit 1; }

clean: ## Remove captures
	@command rm -rf shots
