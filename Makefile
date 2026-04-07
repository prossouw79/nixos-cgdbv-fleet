COMPOSE   := docker compose run --rm nix
# Mark the repo safe for the container's root user (nix fetches it as a git repo)
GIT_SAFE  := git config --global --add safe.directory /repo
HOST      ?= optiplex1

.PHONY: check build eval hosts iso shell clean lock

## Fast: evaluate all configs — catches syntax and type errors without building
## --impure is required because host configs import /etc/nixos/local.nix
check:
	# Stage untracked files on the host (as current user) so nix can see them
	git add -A
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix flake check --no-build --impure'

## Thorough: build the full system closure for a specific host (slow)
## Usage: make build HOST=optiplex2
build:
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix build \
		.#nixosConfigurations.$(HOST).config.system.build.toplevel \
		--option sandbox false \
		--dry-run'

## Evaluate and print the top-level derivation path for a host (faster than build)
## Usage: make eval HOST=optiplex2
eval:
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix eval \
		.#nixosConfigurations.$(HOST).config.system.build.toplevel.drvPath'

## List all hosts defined in flake.nix
hosts:
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix eval .#nixosConfigurations --apply builtins.attrNames'

## Build a bootable installer ISO and copy it to ./nixos-fleet.iso on the host
## Flash to USB: sudo dd if=nixos-fleet.iso of=/dev/sdX bs=4M status=progress conv=fsync
iso:
	git add -A
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix build \
		.#nixosConfigurations.iso.config.system.build.isoImage \
		--option sandbox false && \
		cp -L result/iso/*.iso /repo/nixos-fleet.iso'
	@echo "ISO written to: $(PWD)/nixos-fleet.iso"

## Drop into a nix shell in the container for manual inspection
shell:
	docker compose run --rm --entrypoint sh nix

## Update flake.lock — run this after adding new inputs to flake.nix
lock:
	$(COMPOSE) sh -c '$(GIT_SAFE) && nix flake lock'

## Remove the cached nix store volume (frees disk space)
clean:
	docker compose down -v
