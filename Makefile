# Couch co-op games monorepo. Each game lives in games/<slug>/ with its own
# Makefile; this one holds the shared tools and forwards to a game with G=<slug>.
GODOT_VERSION := 4.7.2
# No G: `make start` opens the TV launcher. G=<slug> picks one game.
G             ?=
GAME_G        := $(or $(G),pixelpals)
SESSION       := pixelpals
# Games that are built (have a Makefile); the rest are plans only.
BUILT         := $(patsubst games/%/Makefile,%,$(wildcard games/*/Makefile))

C  := \033[36m
G_ := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help list setup setup-tools start demo test shots launcher launcher-window covers install-desktop tmux tmux-d tmux-n tmux-new-session

help: ## Show this help
	@echo -e "  $(G_)On the TV: make launcher$(R)  (any pad or keyboard picks a game; hold Back+Start or Ctrl+Q to leave a game)"
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-16s$(R) %s\n", $$1, $$2}'
	@echo -e "  Per game: $(Y)make -C games/<slug> help$(R)   (built: $(BUILT))"

list: ## List every game and its status
	@for d in games/*/; do s=$$(basename $$d); \
		if [ -f $$d/Makefile ]; then st="$(G_)playable$(R)"; else st="$(Y)plan$(R)"; fi; \
		t=$$(grep -m1 '^# ' $$d/PLAN.md $$d/README.md 2>/dev/null | head -1 | sed 's/^[^#]*# //'); \
		printf "  %-22s %b  %s\n" "$$s" "$$st" "$$t"; done

setup-tools: ## Download the pinned Godot binary into .tools/ and sync the Python venv
	@mkdir -p .tools
	@if [ ! -x .tools/Godot_v$(GODOT_VERSION)-stable_linux.x86_64 ]; then \
		echo -e "$(C)Godot $(GODOT_VERSION) -> .tools/$(R)"; \
		curl -sSLo .tools/godot.zip https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/Godot_v$(GODOT_VERSION)-stable_linux.x86_64.zip && \
		unzip -qo .tools/godot.zip -d .tools && command rm -f .tools/godot.zip; fi
	@ln -sf Godot_v$(GODOT_VERSION)-stable_linux.x86_64 .tools/godot
	@uv sync --quiet

setup: setup-tools ## Shared tools, then set up every built game
	@for g in $(BUILT); do $(MAKE) --no-print-directory -C games/$$g setup; done

start: ## Open the TV launcher (or play one game directly: make start G=<slug>)
	@if [ -n "$(G)" ]; then $(MAKE) --no-print-directory -C games/$(G) start; \
	else $(MAKE) --no-print-directory -C launcher start; fi

demo: ## Watch a game play itself (G=pixelpals)
	@$(MAKE) --no-print-directory -C games/$(GAME_G) demo

test: ## Run the tests of every built game, then the launcher's
	@for g in $(BUILT); do echo -e "$(C)== $$g$(R)"; $(MAKE) --no-print-directory -C games/$$g test || exit 1; done
	@echo -e "$(C)== launcher$(R)"; $(MAKE) --no-print-directory -C launcher test

shots: ## Capture every screen of a game (G=pixelpals)
	@$(MAKE) --no-print-directory -C games/$(GAME_G) shots

launcher: ## Play on the TV: the game launcher, fullscreen (any pad or the keyboard)
	@$(MAKE) --no-print-directory -C launcher start

launcher-window: ## The launcher in a 1280x720 window, games windowed too (development)
	@$(MAKE) --no-print-directory -C launcher window

covers: ## Capture each committed game's cover.png from its demo (then LOOK at launcher/shots/covers.png)
	@uv run --quiet python launcher/tools/covers.py

install-desktop: ## Add "Couch Games" to the desktop app menu (~/.local/share/applications)
	@mkdir -p $(HOME)/.local/share/applications
	@printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Couch Games' \
		'Comment=Pick a couch co-op game with a controller' \
		'Exec=make -C $(CURDIR) launcher' 'Icon=$(CURDIR)/launcher/game/icon.png' \
		'Terminal=false' 'Categories=Game;' 'StartupNotify=false' \
		> $(HOME)/.local/share/applications/couch-games.desktop
	@command -v update-desktop-database >/dev/null && update-desktop-database -q $(HOME)/.local/share/applications || true
	@echo -e "$(G_)~/.local/share/applications/couch-games.desktop$(R) (icon: launcher/game/icon.png)"

tmux: ## Attach to (or create) the pixelpals tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Grouped session: shared windows, independent navigation
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)

tmux-new-session: tmux-n
