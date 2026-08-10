.PHONY: build-linux

NIX ?= nix --extra-experimental-features "nix-command flakes"

build-linux:
	$(NIX) build .#linux
