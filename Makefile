
.PHONY: setup-qemu build-qemu build-pkgs gen-busybox-initramfs gen-xvisor-initramfs build-all run-xv6 run-xvisor run-linux

NIX ?= nix --extra-experimental-features "nix-command flakes"
INITRAMFS_DIR ?= build/initramfs

setup-qemu:
	$(NIX) develop --ignore-environment '.#qemu' -c \
		git submodule update --init -- qemu
	mkdir -p build/qemu
	cd build/qemu && $(NIX) develop --ignore-environment '../..#qemu' -c \
    ../../qemu/configure \
    --target-list="riscv64-softmmu" \
    --disable-fuse --disable-user --disable-curl --enable-debug

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
	cp --remove-destination ./result/xvisor/build/vmm.bin ./build/xvisor
	cp --remove-destination ./result/xvisor/build/tests/riscv/virt64/basic/firmware.bin ./build/xvisor

gen-busybox-initramfs:
	rm -rf $(INITRAMFS_DIR)
	INITRAMFS_DIR=$(INITRAMFS_DIR) scripts/gen_busybox_initramfs.sh

gen-xvisor-initramfs:
	mkdir -p $(INITRAMFS_DIR)/system $(INITRAMFS_DIR)/images/riscv/virt64
	cp xvisor/docs/banner/roman.txt $(INITRAMFS_DIR)/system/banner.txt
	cp xvisor/docs/logo/xvisor_logo_name.ppm $(INITRAMFS_DIR)/system/logo.ppm
	dtc -q -I dts -O dtb -o $(INITRAMFS_DIR)/images/riscv/virt64-guest.dtb xvisor/tests/riscv/virt64/virt64-guest.dts
	cp build/xvisor/firmware.bin $(INITRAMFS_DIR)/images/riscv/virt64/firmware.bin
	cp xvisor/tests/riscv/virt64/linux/nor_flash.list $(INITRAMFS_DIR)/images/riscv/virt64/nor_flash.list
	cp xvisor/tests/riscv/virt64/linux/cmdlist $(INITRAMFS_DIR)/images/riscv/virt64/cmdlist
	cp xvisor/tests/riscv/virt64/xscript/one_guest_virt64.xscript $(INITRAMFS_DIR)/boot.xscript
	cp build/linux/Image $(INITRAMFS_DIR)/images/riscv/virt64/Image
	dtc -q -I dts -O dtb -o $(INITRAMFS_DIR)/images/riscv/virt64/virt64.dtb xvisor/tests/riscv/virt64/linux/virt64.dts
	cp $(INITRAMFS_DIR)/initramfs.cpio.gz $(INITRAMFS_DIR)/images/riscv/virt64/rootfs.img
	cd $(INITRAMFS_DIR) && find . -print0 | cpio --null --create --format=newc > ../xvisor-initrd.cpio

build-all:
	$(MAKE) setup-qemu
	$(MAKE) build-qemu
	$(MAKE) build-pkgs
	$(MAKE) gen-busybox-initramfs

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
