# Where Are Greyssie and Kira?: one game of the couch-coop monorepo. Godot, GUT
# and the Python venv are shared at the repo root (make setup there).
SHELL         := /bin/bash
ROOT          := ../..
GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := $(ROOT)/.tools/godot
GAME          := game
SESSION       := greyssie-and-kira
SHOT_SCREEN   ?= house
SCREENS       := join select house night party
# Seconds and sheet frames per screen (house/night show a whole round).
SECS_join     := 8
SECS_select   := 5
SECS_house    := 44
SECS_night    := 44
SECS_party    := 17
SHOT_SECONDS  ?= $(or $(SECS_$(SHOT_SCREEN)),8)
SHOT_COUNT    ?= $(if $(filter house night,$(SHOT_SCREEN)),16,8)
# A whole demo day (join -> select -> 4 rounds -> party), headless, in game seconds.
DAY_SECONDS   ?= 600

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export ensure-import import start start-local play demo demo-day editor test sprites sfx sfx-check assets shot shots export-linux clean tmux tmux-d tmux-n tmux-new-session

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
ensure-import: ## Import once when game/.godot is missing (fresh clone); every run/test target depends on it
	@[ -f $(GAME)/.godot/global_script_class_cache.cfg ] || $(MAKE) --no-print-directory import

import: ## Let Godot scan and import the project (needed after new art/audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ensure-import ## Play (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = walker, arrows+Enter = laser, Space/any other key = treats. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

start-local: start ## Same as start (the game has no remote API)

play: start ## Alias of start

demo: ensure-import ## Watch it play itself (SHOT_SCREEN=join|select|house|night|party; join plays a whole day)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

demo-day: ensure-import ## Headless check: a whole demo day runs 4 rounds and then the party, with no errors
	@mkdir -p shots
	@timeout 300 $(GODOT) --headless --path $(GAME) --fixed-fps 30 --quit-after $$(( $(DAY_SECONDS) * 30 )) \
		-- --demo=join --mute > shots/demo-day.txt 2>&1 || true
	@grep -E "^DAY" shots/demo-day.txt || true
	@if grep -E "SCRIPT ERROR|^ERROR" shots/demo-day.txt | grep -v "resources still in use at exit\|ObjectDB instances leaked"; then echo -e "$(Y)errors in shots/demo-day.txt$(R)"; exit 1; fi
	@grep -q "^DAY party" shots/demo-day.txt || { echo -e "$(Y)the day never reached the party (shots/demo-day.txt)$(R)"; exit 1; }
	@echo -e "$(G)demo day OK: 4 rounds, then the party$(R)"

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ensure-import ## Run the GUT test suite headless (a test file that fails to parse fails the run)
	@mkdir -p shots
	@set -o pipefail; $(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | tee shots/test.log
	@if grep -q "Failed to load script\|Parse Error" shots/test.log; then echo -e "$(Y)a test script failed to load (see shots/test.log)$(R)"; exit 1; fi

sprites: ## Render the cats (from data/cats.json), house tiles, furniture and riders to game/art, lint, contact sheets
	@uv run --quiet python tools/sprites.py

sfx: ## Synthesize the meows (from data/cats.json), sound effects and music into game/audio
	@uv run --quiet python tools/sfx.py

sfx-check: ## Same, plus spectrograms and loop seams in shots/sfx/
	@uv run --quiet python tools/sfx.py --check shots/sfx

assets: sprites sfx import ## Rebuild all generated art and audio

shot: ensure-import ## Capture frames of SHOT_SCREEN (join|select|house|night|party) in demo mode -> shots/
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 320x180 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_SCREEN) --mute > shots/$(SHOT_SCREEN)/log.txt 2>&1 || true
	@uv run --quiet python $(ROOT)/shared/tools/shots.py shots/$(SHOT_SCREEN) --count $(SHOT_COUNT)
	@if grep -E "SCRIPT ERROR|^ERROR" shots/$(SHOT_SCREEN)/log.txt | grep -v "resources still in use at exit\|ObjectDB instances leaked"; then echo -e "$(Y)errors in shots/$(SHOT_SCREEN)/log.txt$(R)"; exit 1; fi
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen
	@for s in $(SCREENS); do $(MAKE) --no-print-directory shot SHOT_SCREEN=$$s || exit 1; done

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo $(ROOT)/.tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo $(ROOT)/.tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f $(ROOT)/.tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ensure-import ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/greyssie-and-kira.x86_64
	@echo -e "$(G)build/greyssie-and-kira.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build

tmux: ## Attach to (or create) the greyssie-and-kira tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Grouped session: shared windows, independent navigation
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)

tmux-new-session: tmux-n
