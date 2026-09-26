GODOT_VERSION := 4.7.2
GUT_VERSION   := 9.6.1
GODOT         := .tools/godot
GAME          := game
SESSION       := pixelpals
SHOT_SECONDS  ?= 8
SHOT_SCREEN   ?= level

C  := \033[36m
G  := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help setup setup-export start play demo editor import test sprites sfx assets shot shots export-linux clean tmux tmux-d tmux-n tmux-new-session

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-14s$(R) %s\n", $$1, $$2}'

setup: ## Download the pinned Godot binary, GUT and the Python tool deps
	@echo -e "$(C)Godot $(GODOT_VERSION) -> .tools/$(R)"
	@mkdir -p .tools
	@if [ ! -x .tools/Godot_v$(GODOT_VERSION)-stable_linux.x86_64 ]; then \
		curl -sSLo .tools/godot.zip https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_linux.x86_64.zip && \
		unzip -qo .tools/godot.zip -d .tools && command rm -f .tools/godot.zip; fi
	@ln -sf Godot_v$(GODOT_VERSION)-stable_linux.x86_64 .tools/godot
	@if [ ! -d $(GAME)/addons/gut ]; then \
		echo -e "$(C)GUT $(GUT_VERSION) -> $(GAME)/addons/gut$(R)"; \
		curl -sSLo .tools/gut.zip https://github.com/bitwes/Gut/archive/refs/tags/v$(GUT_VERSION).zip && \
		unzip -qo .tools/gut.zip -d .tools && mkdir -p $(GAME)/addons && cp -r .tools/Gut-$(GUT_VERSION)/addons/gut $(GAME)/addons/ && \
		command rm -rf .tools/gut.zip .tools/Gut-$(GUT_VERSION); fi
	@uv sync --quiet
	@$(MAKE) --no-print-directory import
	@echo -e "$(G)Ready. make start$(R)"

import: ## Let Godot scan and import the project (needed after new art/audio)
	@$(GODOT) --headless --path $(GAME) --import >/dev/null 2>&1 || $(GODOT) --headless --path $(GAME) --editor --quit >/dev/null 2>&1 || true
	@echo -e "$(G)Imported$(R)"

start: ## Run the game (pads and/or keyboard)
	@echo -e "$(C)Keyboard: WASD+Shift = seat 1, arrows+Enter = seat 2, Space/any other key = seat 3. Esc = pause.$(R)"
	@$(GODOT) --path $(GAME)

play: start ## Alias of start

demo: ## Run the game on scripted input (watch it play itself)
	@$(GODOT) --path $(GAME) -- --demo=$(SHOT_SCREEN)

editor: ## Open the Godot editor
	@$(GODOT) --path $(GAME) --editor &

test: ## Run the GUT test suite headless
	@$(GODOT) --headless --path $(GAME) -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

sprites: ## Render art_src/ grids to game/art PNGs, lint them, write the contact sheet
	@uv run --quiet python tools/sprites.py

sfx: ## Synthesize the sound effects and music into game/audio
	@uv run --quiet python tools/sfx.py

assets: sprites sfx import ## Rebuild all generated art and audio

shot: ## Capture frames of SHOT_SCREEN (join|select|level|party) in demo mode -> shots/
	@command rm -rf shots/$(SHOT_SCREEN) && mkdir -p shots/$(SHOT_SCREEN)
	@xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path $(GAME) --resolution 320x180 \
		--write-movie $(CURDIR)/shots/$(SHOT_SCREEN)/f.png --fixed-fps 30 --quit-after $$(( $(SHOT_SECONDS) * 30 )) \
		-- --demo=$(SHOT_SCREEN) --mute >/dev/null 2>&1 || true
	@uv run --quiet python tools/shots.py shots/$(SHOT_SCREEN)
	@echo -e "$(G)shots/$(SHOT_SCREEN)/sheet.png$(R)"

shots: ## Capture every screen
	@for s in join select level party; do $(MAKE) --no-print-directory shot SHOT_SCREEN=$$s; done

setup-export: ## Download the Linux export templates (1.3 GB download, keeps only ~100 MB)
	@d=$$HOME/.local/share/godot/export_templates/$(GODOT_VERSION).stable; \
	if [ -f $$d/linux_release.x86_64 ]; then echo -e "$(G)templates already in $$d$(R)"; exit 0; fi; \
	mkdir -p $$d && curl -SLo .tools/templates.tpz https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_export_templates.tpz && \
	unzip -qjo .tools/templates.tpz 'templates/linux_*x86_64' 'templates/version.txt' -d $$d && command rm -f .tools/templates.tpz && \
	echo -e "$(G)templates -> $$d$(R)"

export-linux: ## Build a standalone Linux binary into build/ (needs make setup-export once; the private pack is NOT included)
	@mkdir -p build
	@$(GODOT) --headless --path $(GAME) --export-release "Linux" ../build/pixelpals.x86_64
	@echo -e "$(G)build/pixelpals.x86_64$(R)"

clean: ## Remove captures and builds
	@command rm -rf shots build

tmux: ## Attach to (or create) the pixelpals tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Grouped session: shared windows, independent navigation
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)

tmux-new-session: tmux-n
