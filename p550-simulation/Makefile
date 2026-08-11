.PHONY: build-linux build-local-linux clean

NIX ?= nix --extra-experimental-features "nix-command flakes"

build-linux:
	$(NIX) build .#linux

build-local-linux:
	$(NIX) develop --ignore-environment '.#linux' -c \
		make -C riscv-linux O=$(CURDIR)/riscv-linux/build mrproper
	mkdir -p riscv-linux/build/scripts
	cp p550.config riscv-linux/build/.config
	cp riscv-linux/scripts/config riscv-linux/build/scripts/config
	$(NIX) develop --ignore-environment '.#linux' -c \
		bash riscv-linux/build/scripts/config \
		--file riscv-linux/build/.config \
		--disable DRM \
		--disable DRM_ESWIN \
		--disable DRM_IMG \
		--disable DRM_IMG_VOLCANIC \
		--disable DRM_POWERVR \
		--disable POWERVR \
		--disable KSM \
		--disable NUMA_BALANCING \
		--disable TRANSPARENT_HUGEPAGE \
		--disable LOCALVERSION_AUTO \
		--enable RISCV_PSE_EXPERIMENT \
		--set-str LOCALVERSION "-p550-custom3"
	$(NIX) develop --ignore-environment '.#linux' -c \
		make -C riscv-linux O=$(CURDIR)/riscv-linux/build olddefconfig
	$(NIX) develop --ignore-environment '.#linux' -c \
		make -C riscv-linux O=$(CURDIR)/riscv-linux/build \
		-j$(shell nproc) Image modules dtbs

clean:
	rm -f result
	$(NIX) develop --ignore-environment '.#linux' -c \
		make -C riscv-linux O=$(CURDIR)/riscv-linux/build clean
