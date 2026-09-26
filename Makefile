# Couch co-op games monorepo. Each game lives in games/<slug>/ with its own
# Makefile; this one holds the shared tools and forwards to a game with G=<slug>.
GODOT_VERSION := 4.7.2
G             ?= pixelpals
SESSION       := pixelpals
# Games that are built (have a Makefile); the rest are plans only.
BUILT         := $(patsubst games/%/Makefile,%,$(wildcard games/*/Makefile))

C  := \033[36m
G_ := \033[32m
Y  := \033[33m
R  := \033[0m

.PHONY: help list setup setup-tools start demo test shots tmux tmux-d tmux-n tmux-new-session

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(C)%-14s$(R) %s\n", $$1, $$2}'
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

start: ## Play a game (G=pixelpals by default)
	@$(MAKE) --no-print-directory -C games/$(G) start

demo: ## Watch a game play itself (G=pixelpals)
	@$(MAKE) --no-print-directory -C games/$(G) demo

test: ## Run the tests of every built game
	@for g in $(BUILT); do echo -e "$(C)== $$g$(R)"; $(MAKE) --no-print-directory -C games/$$g test || exit 1; done

shots: ## Capture every screen of a game (G=pixelpals)
	@$(MAKE) --no-print-directory -C games/$(G) shots

tmux: ## Attach to (or create) the pixelpals tmux session
	@tmux new-session -A -s $(SESSION)

tmux-d: ## Same, detaching every other client first
	@tmux new-session -A -D -s $(SESSION)

tmux-n: ## Grouped session: shared windows, independent navigation
	@tmux has-session -t $(SESSION) 2>/dev/null && tmux new-session -t $(SESSION) \; set-option destroy-unattached on || tmux new-session -A -s $(SESSION)

tmux-new-session: tmux-n
