{
  description = "QEMU + xv6 (riscv64) dev env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let host_system = "x86_64-linux"; in
    let pkgs = import nixpkgs { system = host_system; }; in
    let xv6_build_inputs = [
      pkgs.perl
      pkgs.gnumake
      pkgs.pkgsCross.riscv64.binutils
      pkgs.pkgsCross.riscv64.gcc
    ]; in
    let linux_build_inputs = [
      pkgs.bash
      pkgs.gnumake
      pkgs.binutils
      pkgs.bison
      pkgs.flex
      pkgs.bc
      pkgs.pkgsCross.riscv64.binutils
      pkgs.pkgsCross.riscv64.gcc
    ]; in
    let opensbi_build_inputs = [
      pkgs.bash
      pkgs.python3
      pkgs.gnumake
      pkgs.pkgsCross.riscv64.binutils
      pkgs.pkgsCross.riscv64.gcc
    ]; in
    let xvisor_build_inputs = [
      pkgs.gnumake
      pkgs.dtc
      pkgs.python3
      pkgs.pkgsCross.riscv64-embedded.gcc
      pkgs.pkgsCross.riscv64-embedded.buildPackages.binutils
    ]; in
    let busybox_build_inputs = [
      pkgs.cpio
      pkgs.dtc
      pkgs.pkgsCross.riscv64-musl.gnumake
      pkgs.pkgsCross.riscv64-musl.pkgsStatic.glib
      pkgs.pkgsCross.riscv64-musl.pkgsStatic.gcc
      pkgs.pkgsCross.riscv64-musl.gcc
      pkgs.pkgsCross.riscv64-musl.glib
      pkgs.gcc
    ]; in
    let qemu_build_inputs = [
      pkgs.clang
      pkgs.python313
      pkgs.python313Packages.distlib
      pkgs.ninja
      pkgs.pkg-config
      pkgs.glib
      pkgs.git
      pkgs.openssh
      pkgs.ncurses
    ]; in
    let mk_qemu_pkg = { debug ? false }:
      pkgs.stdenv.mkDerivation {
        pname = "qemu-pse-riscv64" + pkgs.lib.optionalString debug "-debug";
        version = "10.0.0-pse-a1271b7";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "qemu";
          rev = "a1271b7c545dd4e0bd9ccdfc74592fecd032553a";
          hash = "sha256-/Lc4Z+GBQAtzESytfoOxItKvIn6smAakj4gCxH3m82U=";
        };

        keycodemapdb = pkgs.fetchzip {
          url = "https://gitlab.com/qemu-project/keycodemapdb/-/archive/f5772a62ec52591ff6870b7e8ef32482371f22c6/keycodemapdb-f5772a62ec52591ff6870b7e8ef32482371f22c6.tar.gz";
          hash = "sha256-GbZ5mrUYLXMi0IX4IZzles0Oyc095ij2xAsiLNJwfKQ=";
        };

        dtc = pkgs.fetchzip {
          url = "https://gitlab.com/qemu-project/dtc/-/archive/b6910bec11614980a21e46fbccc35934b671bd81/dtc-b6910bec11614980a21e46fbccc35934b671bd81.tar.gz";
          hash = "sha256-gx9LG3U9etWhPxm7Ox7rOu9X5272qGeHqZtOe68zFs4=";
        };

        nativeBuildInputs = qemu_build_inputs;
        hardeningDisable = [ "fortify" ];
        dontStrip = debug;

        postPatch = ''
          cp -R "$keycodemapdb" subprojects/keycodemapdb
          cp -R "$dtc" subprojects/dtc
          chmod -R u+w subprojects/keycodemapdb subprojects/dtc
          patchShebangs scripts subprojects/keycodemapdb/tools
          substituteInPlace meson.build \
            --replace-fail "if host_os != 'emscripten'" "if false"
        '';

        configurePhase = ''
          runHook preConfigure
          export CC=clang
          ./configure \
            --prefix="$out" \
            --target-list=riscv64-softmmu \
            --disable-download \
            --disable-fuse \
            --disable-user \
            --disable-curl \
            ${pkgs.lib.optionalString debug "--enable-debug"} \
            -Dfdt=internal
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ninja -C build qemu-system-riscv64
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp build/qemu-system-riscv64 "$out/bin/"
          runHook postInstall
        '';

        meta.mainProgram = "qemu-system-riscv64";
      };
    in
    let qemu_pkg = mk_qemu_pkg { };
    in
    let qemu_debug_pkg = mk_qemu_pkg { debug = true; };
    in
    let qemu_shell =
      pkgs.mkShell {
        hardeningDisable = [ "fortify" ];
        packages = qemu_build_inputs;
        shellHook = ''
          export CC=clang
        '';
      };
    in
    let xv6_shell =
      pkgs.mkShell {
        packages = xv6_build_inputs;
      };
    in
    let xvisor_shell =
      pkgs.mkShell {
        packages = xvisor_build_inputs;
        shellHook = ''
          export ARCH=riscv
          export CROSS_COMPILE=riscv64-none-elf-
        '';
      };
    in
    let linux_shell =
      pkgs.mkShell {
        packages = linux_build_inputs;
        shellHook = ''
          export ARCH=riscv
          export CROSS_COMPILE=riscv64-unknown-linux-gnu-
        '';
      };
    in
    let opensbi_shell =
      pkgs.mkShell {
        packages = opensbi_build_inputs;
        shellHook = ''
          export CROSS_COMPILE=riscv64-unknown-linux-gnu-
          export PLATFORM=generic
          export FW_TEXT_START=0x80000000
        '';
      };
    in
    let busybox_shell =
      pkgs.mkShell {
        packages = busybox_build_inputs;
        shellHook = ''
          export ARCH=riscv
          export CROSS_COMPILE=riscv64-unknown-linux-musl-
        '';
      };
    in
    let xv6_pkg =
      pkgs.stdenv.mkDerivation {
        name = "xv6-riscv-pse";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "xv6-riscv";
          rev = "8662adf08ee541b54d4ec6b44881973d9f6f5e62";
          sha256 = "sha256-xDORtJ4piDz/sWSGPJtbdPUsfCqew9FFdlcxEfzaCy0=";
        };

        nativeBuildInputs = xv6_build_inputs;

        buildPhase = ''
          make fs.img kernel/kernel -j$(nproc)
        '';

        installPhase =''
          mkdir -p $out/xv6/build
          cp -r $PWD/fs.img $PWD/kernel/kernel $out/xv6/build
        '';
      };
    in
    let linux_pkg =
      pkgs.stdenv.mkDerivation {
        name = "linux-kernel-pse";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "linux";
          rev = "b320789d6883cc00ac78ce83bccbfe7ed58afcf0";
          sha256 = "sha256-xuwSwpzFV/YVHrSqJMQRjoMPhFzufP999bLfPGzyXO4=";
        };

        nativeBuildInputs = linux_build_inputs;

        configurePhase = ''
          export O=$PWD/build
          mkdir -p $PWD/$O

          make -C $src O=$O ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig

          mkdir -p $O/scripts/ && cp $src/scripts/config $O/scripts/config
          substituteInPlace $O/scripts/config --replace-fail '#!/usr/bin/env bash' "#!$SHELL"

          $O/scripts/config --file $O/.config -d CONFIG_DRM -d CONFIG_TRANSPARENT_HUGEPAGE
        '';

        buildPhase = ''
          make -C $src O=$O ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- -j$(nproc) Image
        '';

        installPhase =''
          mkdir -p $out/linux/build
          cp -r $PWD/build/arch/riscv/boot/Image $out/linux/build/Image
        '';
      };
    in
    let opensbi_pkg =
      pkgs.stdenv.mkDerivation {
        name = "opensbi-pse";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "opensbi";
          rev = "f6e15b228491c3df87e35124a2e10aba65084b62";
          sha256 = "sha256-8U3rThmhoAfz9QmHYi0PF5d8SLknGy0zIDYZ3a7WvOI=";
        };

        nativeBuildInputs = opensbi_build_inputs;

        configurePhase = ''
          substituteInPlace $PWD/scripts/Kconfiglib/defconfig.py --replace-fail '#!/usr/bin/env python3' "#!$(command -v python3)"
          substituteInPlace $PWD/scripts/Kconfiglib/genconfig.py --replace-fail '#!/usr/bin/env python3' "#!$(command -v python3)"
          substituteInPlace $PWD/scripts/carray.sh --replace-fail '#!/usr/bin/env bash' "#!$SHELL"
        '';

        buildPhase = ''
          CROSS_COMPILE='riscv64-unknown-linux-gnu-' PLATFORM='generic' FW_TEXT_START='0x80000000' make -j$(nproc)
        '';

        installPhase = ''
          mkdir -p $out/opensbi
          make PLATFORM='generic' I=$out/opensbi install
        '';
      };
    in
    let xvisor_pkg =
      pkgs.stdenv.mkDerivation {
        name = "xvisor-pse";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "xvisor";
          rev = "03109cd214783a5fe1eda4a7538547239a3b0095";
          sha256 = "sha256-mLIIHgIRMaN87dvI36tTa2mTTzKbAqqETXQsqhJy2hg=";
        };

        nativeBuildInputs = xvisor_build_inputs;

        configurePhase = ''
          patchShebangs tools
          make O=$PWD/build \
            ARCH=riscv \
            CROSS_COMPILE=riscv64-none-elf- \
            generic-64b-defconfig
        '';

        buildPhase = ''
          make ARCH=riscv CROSS_COMPILE=riscv64-none-elf- -j$(nproc) VERBOSE=y
          make -C tests/riscv/virt64/basic \
            ARCH=riscv \
            CROSS_COMPILE=riscv64-none-elf- \
            -j$(nproc) VERBOSE=y
        '';

        installPhase = ''
          mkdir -p $out/xvisor/build
          cp build/vmm.bin $out/xvisor/build/vmm.bin
          cp build/tests/riscv/virt64/basic/firmware.bin $out/xvisor/build/firmware.bin
          cp docs/banner/roman.txt $out/xvisor/build/banner.txt
          cp docs/logo/xvisor_logo_name.ppm $out/xvisor/build/logo.ppm
          cp tests/riscv/virt64/linux/nor_flash.list $out/xvisor/build/nor_flash.list
          cp tests/riscv/virt64/linux/cmdlist $out/xvisor/build/cmdlist
          cp tests/riscv/virt64/xscript/one_guest_virt64.xscript $out/xvisor/build/boot.xscript
          dtc -q -I dts -O dtb \
            -o $out/xvisor/build/virt64-guest.dtb \
            tests/riscv/virt64/virt64-guest.dts
          dtc -q -I dts -O dtb \
            -o $out/xvisor/build/virt64.dtb \
            tests/riscv/virt64/linux/virt64.dts
        '';
      };
    in
    let busybox_pkg =
      pkgs.pkgsCross.riscv64-musl.stdenv.mkDerivation {
        name = "busybox-pse";

        src = pkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "busybox";
          rev = "b4cedd4c9ae0ea31986973b7b3e6956937aafa32";
          sha256 = "sha256-l01uowQ5vtmm8pbMAvx8L79ETx92XcHFDKyfO5zRPAw=";
        };

        nativeBuildInputs = busybox_build_inputs;

        configurePhase = ''
          CROSS_COMPILE='riscv64-unknown-linux-musl-' ARCH='riscv' make V=1 defconfig
          substituteInPlace .config --replace-fail 'CONFIG_TC=y' 'CONFIG_TC=n'
          substituteInPlace .config --replace-fail 'CONFIG_FEATURE_TC_INGRESS=y' 'CONFIG_FEATURE_TC_INGRESS=n'
          substituteInPlace .config --replace-fail '# CONFIG_STATIC is not set' 'CONFIG_STATIC=y'
        '';

        buildPhase = ''
          CROSS_COMPILE='riscv64-unknown-linux-musl-' ARCH='riscv' make V=1 -j$(nproc)
        '';

        installPhase = ''
          mkdir -p $out/busybox
          cp busybox $out/busybox/
        '';
      };
    in
    let linux_initramfs_pkg =
      pkgs.runCommand "linux-initramfs-pse" {
        nativeBuildInputs = [
          pkgs.cpio
          pkgs.fakeroot
          pkgs.findutils
          pkgs.gzip
        ];
      } ''
        root="$TMPDIR/root"
        mkdir -p \
          "$root"/{bin,sbin,dev,etc,home,mnt,proc,sys,usr,tmp} \
          "$root"/usr/{bin,sbin} \
          "$root"/proc/sys/kernel

        cp ${busybox_pkg}/busybox/busybox "$root/bin/busybox"
        install -m 0755 ${pkgs.writeText "pse-init" ''
          #!/bin/busybox sh
          /bin/busybox --install -s
          mount -t devtmpfs devtmpfs /dev
          mount -t proc proc /proc
          mount -t sysfs sysfs /sys
          mount -t tmpfs tmpfs /tmp
          setsid cttyhack sh
          echo /sbin/mdev > /proc/sys/kernel/hotplug
          mdev -s
          sh
        ''} "$root/init"

        fakeroot -s "$TMPDIR/fakeroot.state" -- \
          mknod "$root/dev/sda" b 8 0
        fakeroot -i "$TMPDIR/fakeroot.state" -s "$TMPDIR/fakeroot.state" -- \
          mknod "$root/dev/console" c 5 1

        find "$root" -exec touch -h -d '@1' {} +
        mkdir -p "$out"
        cd "$root"
        find . -print0 \
          | sort -z \
          | fakeroot -i "$TMPDIR/fakeroot.state" -- \
              cpio --null --create --format=newc --owner=0:0 --reproducible \
          | gzip -9n > "$out/initramfs.cpio.gz"
      '';
    in
    let xvisor_initramfs_pkg =
      pkgs.runCommand "xvisor-initramfs-pse" {
        nativeBuildInputs = [ pkgs.cpio pkgs.findutils ];
      } ''
        root="$TMPDIR/root"
        mkdir -p "$root/system" "$root/images/riscv/virt64"

        cp ${xvisor_pkg}/xvisor/build/banner.txt "$root/system/banner.txt"
        cp ${xvisor_pkg}/xvisor/build/logo.ppm "$root/system/logo.ppm"
        cp ${xvisor_pkg}/xvisor/build/virt64-guest.dtb "$root/images/riscv/virt64-guest.dtb"
        cp ${xvisor_pkg}/xvisor/build/firmware.bin "$root/images/riscv/virt64/firmware.bin"
        cp ${xvisor_pkg}/xvisor/build/nor_flash.list "$root/images/riscv/virt64/nor_flash.list"
        cp ${xvisor_pkg}/xvisor/build/cmdlist "$root/images/riscv/virt64/cmdlist"
        cp ${xvisor_pkg}/xvisor/build/boot.xscript "$root/boot.xscript"
        cp ${linux_pkg}/linux/build/Image "$root/images/riscv/virt64/Image"
        cp ${xvisor_pkg}/xvisor/build/virt64.dtb "$root/images/riscv/virt64/virt64.dtb"
        cp ${linux_initramfs_pkg}/initramfs.cpio.gz "$root/images/riscv/virt64/rootfs.img"

        find "$root" -exec touch -h -d '@1' {} +
        mkdir -p "$out"
        cd "$root"
        find . -print0 \
          | sort -z \
          | cpio --null --create --format=newc --owner=0:0 --reproducible \
          > "$out/xvisor-initrd.cpio"
      '';
    in
    let xv6_runner =
      pkgs.writeShellScriptBin "run-xv6" ''
        qemu=${qemu_pkg}/bin/qemu-system-riscv64
        if [[ "''${1:-}" == "--debug" ]]; then
          qemu=${qemu_debug_pkg}/bin/qemu-system-riscv64
          shift
        fi

        exec "$qemu" \
          -M virt \
          -m 256M \
          -smp 1 \
          -nographic \
          -global virtio-mmio.force-legacy=false \
          -drive file=${xv6_pkg}/xv6/build/fs.img,if=none,format=raw,id=x0 \
          -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
          -snapshot \
          -bios none \
          -kernel ${xv6_pkg}/xv6/build/kernel \
          "$@"
      '';
    in
    let linux_runner =
      pkgs.writeShellScriptBin "run-linux" ''
        qemu=${qemu_pkg}/bin/qemu-system-riscv64
        if [[ "''${1:-}" == "--debug" ]]; then
          qemu=${qemu_debug_pkg}/bin/qemu-system-riscv64
          shift
        fi

        exec "$qemu" \
          -M virt \
          -m 256M \
          -smp 1 \
          -nographic \
          -global virtio-mmio.force-legacy=false \
          -bios ${opensbi_pkg}/opensbi/share/opensbi/lp64/generic/firmware/fw_dynamic.bin \
          -kernel ${linux_pkg}/linux/build/Image \
          -initrd ${linux_initramfs_pkg}/initramfs.cpio.gz \
          -append "console=ttyS0 init=/init" \
          "$@"
      '';
    in
    let xvisor_runner =
      pkgs.writeShellScriptBin "run-xvisor" ''
        qemu=${qemu_pkg}/bin/qemu-system-riscv64
        if [[ "''${1:-}" == "--debug" ]]; then
          qemu=${qemu_debug_pkg}/bin/qemu-system-riscv64
          shift
        fi

        exec "$qemu" \
          -M virt \
          -m 512M \
          -nographic \
          -bios ${opensbi_pkg}/opensbi/share/opensbi/lp64/generic/firmware/fw_dynamic.bin \
          -kernel ${xvisor_pkg}/xvisor/build/vmm.bin \
          -initrd ${xvisor_initramfs_pkg}/xvisor-initrd.cpio \
          -append 'vmm.bootcmd="vfs mount initrd /; vfs run /boot.xscript; guest kick guest0; vserial bind guest0/uart0;"' \
          "$@"
      '';
    in
    {
      apps.x86_64-linux.linux = {
        type = "app";
        program = "${linux_runner}/bin/run-linux";
      };
      apps.x86_64-linux.xv6 = {
        type = "app";
        program = "${xv6_runner}/bin/run-xv6";
      };
      apps.x86_64-linux.xvisor = {
        type = "app";
        program = "${xvisor_runner}/bin/run-xvisor";
      };
      devShells.x86_64-linux = {
        qemu = qemu_shell;
        xv6 = xv6_shell;
        linux = linux_shell;
        xvisor = xvisor_shell;
        opensbi = opensbi_shell;
        busybox = busybox_shell;
      };
      packages.x86_64-linux.default = pkgs.symlinkJoin {
        name = "pse-packages";

        paths = [
          xv6_pkg
          linux_pkg
          opensbi_pkg
          xvisor_pkg
          busybox_pkg
          qemu_pkg
          linux_initramfs_pkg
          xvisor_initramfs_pkg
        ];
      };
      packages.x86_64-linux.linux-initramfs = linux_initramfs_pkg;
      packages.x86_64-linux.qemu = qemu_pkg;
      packages.x86_64-linux.qemu-debug = qemu_debug_pkg;
      packages.x86_64-linux.xvisor = xvisor_pkg;
      packages.x86_64-linux.xvisor-initramfs = xvisor_initramfs_pkg;
    };
}
