
.PHONY: setup-qemu build-qemu build-pkgs gen-busybox-initramfs gen-xvisor-initramfs build-all run-xv6 run-xvisor run-linux

NIX ?= nix --extra-experimental-features "nix-command flakes"
INITRAMFS_DIR ?= build/initramfs
QEMU_DEBUG ?= 0
QEMU_CONFIGURE_FLAGS := --target-list="riscv64-softmmu" \
	--disable-fuse --disable-user --disable-curl

ifeq ($(QEMU_DEBUG),1)
QEMU_CONFIGURE_FLAGS += --enable-debug
else ifneq ($(QEMU_DEBUG),0)
$(error QEMU_DEBUG must be either 0 or 1)
endif

setup-qemu:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		git submodule update --init -- qemu
	mkdir -p build/qemu
	cd build/qemu && $(NIX) develop --ignore-environment '../..#qemu' -c \
		../../qemu/configure $(QEMU_CONFIGURE_FLAGS)

build-qemu:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		make -C build/qemu -j$(shell nproc)

build-pkgs:
	$(NIX) build . -L
	mkdir -p build/xv6
	mkdir -p build/linux
	mkdir -p build/opensbi
	mkdir -p build/busybox
	mkdir -p build/xvisor
	cp --remove-destination ./result/xv6/build/fs.img ./result/xv6/build/kernel ./build/xv6
	chmod u+w ./build/xv6/fs.img
	cp --remove-destination ./result/linux/build/Image ./build/linux
	cp --remove-destination ./result/opensbi/share/opensbi/lp64/generic/firmware/fw_dynamic.bin ./build/opensbi
	cp --remove-destination ./result/busybox/busybox ./build/busybox
	cp --remove-destination \
		./result/xvisor/build/vmm.bin \
		./result/xvisor/build/firmware.bin \
		./result/xvisor/build/banner.txt \
		./result/xvisor/build/logo.ppm \
		./result/xvisor/build/nor_flash.list \
		./result/xvisor/build/cmdlist \
		./result/xvisor/build/boot.xscript \
		./result/xvisor/build/virt64-guest.dtb \
		./result/xvisor/build/virt64.dtb \
		./build/xvisor

gen-busybox-initramfs:
	rm -rf $(INITRAMFS_DIR)
	INITRAMFS_DIR=$(INITRAMFS_DIR) scripts/gen_busybox_initramfs.sh

gen-xvisor-initramfs:
	mkdir -p $(INITRAMFS_DIR)/system $(INITRAMFS_DIR)/images/riscv/virt64
	cp --remove-destination build/xvisor/banner.txt $(INITRAMFS_DIR)/system/banner.txt
	cp --remove-destination build/xvisor/logo.ppm $(INITRAMFS_DIR)/system/logo.ppm
	cp --remove-destination build/xvisor/virt64-guest.dtb $(INITRAMFS_DIR)/images/riscv/virt64-guest.dtb
	cp --remove-destination build/xvisor/firmware.bin $(INITRAMFS_DIR)/images/riscv/virt64/firmware.bin
	cp --remove-destination build/xvisor/nor_flash.list $(INITRAMFS_DIR)/images/riscv/virt64/nor_flash.list
	cp --remove-destination build/xvisor/cmdlist $(INITRAMFS_DIR)/images/riscv/virt64/cmdlist
	cp --remove-destination build/xvisor/boot.xscript $(INITRAMFS_DIR)/boot.xscript
	cp --remove-destination build/linux/Image $(INITRAMFS_DIR)/images/riscv/virt64/Image
	cp --remove-destination build/xvisor/virt64.dtb $(INITRAMFS_DIR)/images/riscv/virt64/virt64.dtb
	cp --remove-destination $(INITRAMFS_DIR)/initramfs.cpio.gz $(INITRAMFS_DIR)/images/riscv/virt64/rootfs.img
	cd $(INITRAMFS_DIR) && find . -print0 | cpio --null --create --format=newc > ../xvisor-initrd.cpio

build-all:
	$(MAKE) setup-qemu QEMU_DEBUG=0
	$(MAKE) build-qemu
	$(MAKE) build-pkgs
	$(MAKE) gen-busybox-initramfs
	$(MAKE) gen-xvisor-initramfs

run-xv6:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		build/qemu/qemu-system-riscv64 \
		-M virt \
		-m 256M \
		-smp 1 \
		-nographic \
		-global virtio-mmio.force-legacy=false \
		-drive file=./build/xv6/fs.img,if=none,format=raw,id=x0 \
		-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
		-bios none \
		-kernel ./build/xv6/kernel

run-xvisor:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		build/qemu/qemu-system-riscv64 \
		-M virt \
		-m 512M \
		-nographic \
		-bios ./build/opensbi/fw_dynamic.bin \
		-kernel ./build/xvisor/vmm.bin \
		-initrd ./build/xvisor-initrd.cpio \
		-append 'vmm.bootcmd="vfs mount initrd /; vfs run /boot.xscript; guest kick guest0; vserial bind guest0/uart0;"'

run-linux:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		build/qemu/qemu-system-riscv64 \
		-M virt \
		-m 256M \
		-smp 1 \
		-nographic \
		-global virtio-mmio.force-legacy=false \
		-bios ./build/opensbi/fw_dynamic.bin \
		-kernel ./build/linux/Image \
		-initrd ./build/initramfs/initramfs.cpio.gz \
		-append "console=ttyS0 init=/init"

clean:
	rm result
	rm -rf build
