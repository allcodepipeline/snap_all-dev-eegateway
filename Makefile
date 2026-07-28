# Copyright (c) 2026 - Licensed under GPL-3.0-only (upstream) / packaging Apache-2.0 style Makefile

.PHONY: help clean git-pull build build-lxd all

PROJECT_NAME := $(shell awk '/^name:/{print $$2}' snap/snapcraft.yaml 2>/dev/null)
VERSION := $(shell awk -F"'" '/^version:/{print $$2}' snap/snapcraft.yaml 2>/dev/null)
SNAP_FILE := $(PROJECT_NAME)_$(VERSION)_amd64.snap

BUILD_DIR := build
DIST_DIR := dist
SNAPCRAFT ?= snapcraft
SNAPCRAFT_FLAGS ?= --destructive-mode --verbosity=verbose

RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
CYAN = \033[0;36m
BOLD = \033[1m
NC = \033[0m

CHECK = ✅
CROSS = ❌
ARROW = ➤
PACKAGE = 📦
CLEAN = 🧹

all: clean git-pull build

help:
	@echo ""
	@echo "$(BOLD)$(BLUE)$(PROJECT_NAME) Snap Build$(NC)"
	@echo "$(CYAN)=====================================$(NC)"
	@echo ""
	@echo "Snap: $(PROJECT_NAME) $(VERSION)"
	@echo ""
	@echo "$(BOLD)Available targets:$(NC)"
	@echo "  $(GREEN)help$(NC)       - Show this help message"
	@echo "  $(GREEN)clean$(NC)      - $(CLEAN) Remove build artifacts"
	@echo "  $(GREEN)git-pull$(NC)   - Pull latest changes (skipped if not a git repo)"
	@echo "  $(GREEN)build$(NC)      - $(PACKAGE) Build snap (destructive mode, needs sudo)"
	@echo "  $(GREEN)build-lxd$(NC)  - $(PACKAGE) Build snap in LXD (isolated, no sudo)"
	@echo "  $(GREEN)all$(NC)        - clean, git-pull, build"
	@echo ""

clean:
	@echo "$(BOLD)$(BLUE)Cleaning Build Environment$(NC)"
	@echo "$(CYAN)=============================$(NC)"
	@echo "$(BLUE)$(ARROW) Removing build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR) $(DIST_DIR) *.snap parts/ prime/ stage/ snap/.snapcraft/ overlay/ .snapcraft/ >/dev/null 2>&1 || true
	@find . -maxdepth 1 -name "*.log" -type f -delete >/dev/null 2>&1 || true
	@sudo snapcraft clean 2>/dev/null || true
	@echo "$(GREEN)$(CHECK) Clean completed$(NC)"

git-pull:
	@if ! git rev-parse --git-dir >/dev/null 2>&1; then \
		echo "$(YELLOW)Skipping git pull — not a git repository$(NC)"; \
	elif git pull > git_pull.log 2>&1; then \
		echo "$(BOLD)$(BLUE)Updating Source Code$(NC)"; \
		if grep -q "Already up to date." git_pull.log; then \
			echo "$(GREEN)$(CHECK) Repository is already up to date$(NC)"; \
		else \
			echo "$(GREEN)$(CHECK) Source code updated$(NC)"; \
			grep -E "Fast-forward|Updating|files changed" git_pull.log || true; \
		fi; \
		rm -f git_pull.log; \
	else \
		echo "$(RED)$(CROSS) Git pull failed$(NC)" >&2; \
		cat git_pull.log; \
		rm -f git_pull.log; \
		exit 1; \
	fi

build: git-pull
	@test -n "$(PROJECT_NAME)" || (echo "$(RED)$(CROSS) snap/snapcraft.yaml not found or missing name:$(NC)" >&2; exit 1)
	@echo "$(BOLD)$(BLUE)Building Snap Package$(NC)"
	@echo "$(CYAN)======================$(NC)"
	@echo "$(BLUE)$(ARROW) $(PROJECT_NAME) $(VERSION)$(NC)"
	@mkdir -p $(DIST_DIR)
	@if sudo $(SNAPCRAFT) pack $(SNAPCRAFT_FLAGS) | tee build.log; then \
		if [ -f "$(SNAP_FILE)" ]; then \
			mv -f "$(SNAP_FILE)" "$(DIST_DIR)/"; \
			echo "$(GREEN)$(CHECK) Built $(DIST_DIR)/$(SNAP_FILE)$(NC)"; \
		else \
			GENERATED_SNAP=$$(ls $(PROJECT_NAME)_*_amd64.snap 2>/dev/null | head -n 1); \
			if [ -n "$$GENERATED_SNAP" ]; then \
				mv -f "$$GENERATED_SNAP" "$(DIST_DIR)/"; \
				echo "$(GREEN)$(CHECK) Built $(DIST_DIR)/$$GENERATED_SNAP$(NC)"; \
			else \
				echo "$(RED)$(CROSS) No snap file generated$(NC)" >&2; \
				exit 1; \
			fi; \
		fi; \
	else \
		echo "$(RED)$(CROSS) Snapcraft build failed$(NC)" >&2; \
		exit 1; \
	fi

build-lxd: git-pull
	@test -n "$(PROJECT_NAME)" || (echo "$(RED)$(CROSS) snap/snapcraft.yaml not found or missing name:$(NC)" >&2; exit 1)
	@echo "$(BOLD)$(BLUE)Building Snap Package (LXD)$(NC)"
	@mkdir -p $(DIST_DIR)
	@$(SNAPCRAFT) pack --use-lxd --verbosity=verbose | tee build.log
	@test -f "$(SNAP_FILE)" || (echo "$(RED)$(CROSS) Expected $(SNAP_FILE)$(NC)" >&2; exit 1)
	@mv -f "$(SNAP_FILE)" "$(DIST_DIR)/"
	@echo "$(GREEN)$(CHECK) Built $(DIST_DIR)/$(SNAP_FILE)$(NC)"
