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
    {
      devShells.x86_64-linux = {
        qemu = qemu_shell;
        xv6 = xv6_shell;
        linux = linux_shell;
        xvisor = xvisor_shell;
        opensbi = opensbi_shell;
        busybox = busybox_shell;
      };
      packages.x86_64-linux.default = pkgs.symlinkJoin {
        name = "combined";

        paths = [
          xv6_pkg
          linux_pkg
          opensbi_pkg
          xvisor_pkg
          busybox_pkg
        ];
      };
      packages.x86_64-linux.xvisor = xvisor_pkg;
    };
}
