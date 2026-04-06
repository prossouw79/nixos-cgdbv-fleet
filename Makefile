COMPOSE := docker compose run --rm nix
# Nix fetches the flake as a git repo; mark it safe for the container's root user.
# git add -A stages any untracked files so nix can see them (nix only sees tracked files).
GIT_SETUP := git config --global --add safe.directory /repo && git add -A
HOST      ?= optiplex1

.PHONY: check build eval hosts shell clean

## Fast: evaluate all configs — catches syntax and type errors without building
## --impure is required because host configs import /etc/nixos/local.nix
check:
	$(COMPOSE) sh -c '$(GIT_SETUP) && nix flake check --no-build --impure'

## Thorough: build the full system closure for a specific host (slow)
## Usage: make build HOST=optiplex2
build:
	$(COMPOSE) sh -c '$(GIT_SETUP) && nix build \
		.#nixosConfigurations.$(HOST).config.system.build.toplevel \
		--option sandbox false \
		--dry-run'

## Evaluate and print the top-level derivation path for a host (faster than build)
## Usage: make eval HOST=optiplex2
eval:
	$(COMPOSE) sh -c '$(GIT_SETUP) && nix eval \
		.#nixosConfigurations.$(HOST).config.system.build.toplevel.drvPath'

## List all hosts defined in flake.nix
hosts:
	$(COMPOSE) sh -c '$(GIT_SETUP) && nix eval .#nixosConfigurations --apply builtins.attrNames'

## Drop into a nix shell in the container for manual inspection
shell:
	docker compose run --rm --entrypoint sh nix

## Remove the cached nix store volume (frees disk space)
clean:
	docker compose down -v
