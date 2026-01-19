.DEFAULT_GOAL := help

SHELL := bash

REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)

# --------------------------------------------------------------------
# Configuration knobs
#
# Note: Airlock supports `~/.airlock/config.toml` defaults (see docs/configuration.md). To preserve
# precedence (CLI/env > config > built-ins), this Makefile intentionally does not export any
# Airlock defaults.
#
# Override per-invocation like:
#   AIRLOCK_ENGINE=docker make test
#   make test AIRLOCK_ENGINE=docker
# --------------------------------------------------------------------

## Show help (default).
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nAirlock SDLC targets\n\nUsage:\n  make <target> [VAR=val ...]\n\nTargets:\n"} \
	/^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-22s %s\n", $$1, $$2} \
	END {printf "\nUseful vars (override per-invocation):\n"; \
	     printf "  AIRLOCK_ENGINE=podman|docker|nerdctl (default: podman)\n"; \
	     printf "  AIRLOCK_PULL=1|0, AIRLOCK_BUILD_ISOLATION=..., AIRLOCK_NPM_VERSION=..., AIRLOCK_CODEX_VERSION=..., AIRLOCK_OPENCODE_VERSION=..., AIRLOCK_EDITOR_PKG=...\n"; \
	     printf "  AIRLOCK_SYSTEM_REBUILD=1 (force smoke rebuild), AIRLOCK_SYSTEM_CLEAN_IMAGE=1 (delete image built by smoke)\n\n"}' \
	$(MAKEFILE_LIST)
.PHONY: help

# --------------------
# Dependencies
# --------------------

## Check required host tools (fails fast instead of skipping).
deps-check: ## Verify prerequisites for lint/tests.
	@set -euo pipefail; \
	missing=0; \
	check() { command -v "$$1" >/dev/null 2>&1 || { echo "ERROR: missing $$1" >&2; missing=1; }; }; \
	check git; \
	check npx; \
	check stow; \
	check shellcheck; \
	if ! command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1 && ! command -v nerdctl >/dev/null 2>&1; then \
	  echo "ERROR: missing container engine (need podman, docker, or nerdctl)" >&2; missing=1; \
	fi; \
	[[ "$$missing" -eq 0 ]]
.PHONY: deps-check

## Install prerequisites on Debian/Ubuntu (uses sudo).
deps-apt: ## Install deps via apt-get (Debian/Ubuntu).
	@set -euo pipefail; \
	sudo apt-get update; \
	sudo apt-get install -y git stow shellcheck nodejs npm
.PHONY: deps-apt

# --------------------
# Quality gates (CI)
# --------------------

## Run all checks (lint + unit + system smoke).
test: deps-check ## Run lint + unit + smoke.
	@cd "$(REPO_ROOT)" && ./scripts/test.sh
.PHONY: test

## Run lint only (shellcheck + markdownlint via npx fallback).
lint: ## Run lint only.
	@cd "$(REPO_ROOT)" && ./scripts/test-lint.sh
.PHONY: lint

## Run unit tests only (engine-free).
unit: ## Run unit tests only.
	@cd "$(REPO_ROOT)" && ./scripts/test-unit.sh
.PHONY: unit

## Run system smoke test (reuses `airlock-agent:local` unless rebuild is needed).
smoke: deps-check ## Run system smoke test.
	@cd "$(REPO_ROOT)" && ./scripts/test-system.sh
.PHONY: smoke

## Run system smoke test for Docker-in-Docker (`yolo --dind`).
smoke-dind: deps-check ## Run system DinD smoke test.
	@cd "$(REPO_ROOT)" && ./scripts/test-system-dind.sh
.PHONY: smoke-dind

## Force smoke to rebuild the image (use after changing `stow/airlock/.airlock/image/*`).
smoke-rebuild: deps-check ## Force rebuild and run smoke.
	@cd "$(REPO_ROOT)" && AIRLOCK_SYSTEM_REBUILD=1 ./scripts/test-system.sh
.PHONY: smoke-rebuild

## Run the same gates CI should run.
ci: deps-check ## Run CI-equivalent gates.
	@cd "$(REPO_ROOT)" && ./scripts/test.sh
.PHONY: ci

# --------------------
# Install / package
# --------------------

## Install Airlock into your $HOME via GNU Stow (creates `~/bin/yolo`, etc).
install: ## Install via stow into $$HOME.
	@cd "$(REPO_ROOT)" && ./scripts/install.sh
.PHONY: install

## Uninstall Airlock from your $HOME via GNU Stow.
uninstall: ## Uninstall via stow from $$HOME.
	@cd "$(REPO_ROOT)" && ./scripts/uninstall.sh
.PHONY: uninstall

## Reinstall (uninstall + install).
restow: ## Reinstall via stow.
	@cd "$(REPO_ROOT)" && ./scripts/uninstall.sh && ./scripts/install.sh
.PHONY: restow

# --------------------
# Build / run
# --------------------

## Run `airlock-doctor` (requires `make install` once).
doctor: install ## Validate host prerequisites.
	@"$(HOME)/bin/airlock-doctor"
.PHONY: doctor

## Build the agent image (requires `make install` once).
image: install ## Build the agent image.
	@"$(HOME)/bin/airlock-build"
.PHONY: image

## Launch `yolo` (requires `make image` first).
yolo: install ## Launch yolo shell (from current directory).
	@"$(HOME)/bin/yolo"
.PHONY: yolo

## Launch `codex` inside yolo (requires `make image` first).
codex: install ## Launch codex inside yolo.
	@"$(HOME)/bin/yolo" -- codex
.PHONY: codex

## Bootstrap a host install and build the default image.
bootstrap: deps-check install image ## Install and build image.
.PHONY: bootstrap

## Start an interactive yolo shell after bootstrap.
run: bootstrap ## Install, build, and run yolo.
	@"$(HOME)/bin/yolo"
.PHONY: run

## Start Codex after bootstrap.
agent: bootstrap ## Install, build, and run codex.
	@"$(HOME)/bin/yolo" -- codex
.PHONY: agent

# --------------------
# Cleanup
# --------------------

## Remove local test temp dirs.
clean: ## Remove repo-local test temp dirs.
	@cd "$(REPO_ROOT)" && rm -rf .airlock-test-tmp
.PHONY: clean
