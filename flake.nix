{
  description = "QEMU + xv6 (riscv64) dev env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let host_system = "x86_64-linux"; in
    let hostPkgs = import nixpkgs { system = host_system; }; in
    let riscv64Pkgs =
      import nixpkgs {
        system = host_system;
        crossSystem = {
          config = "riscv64-unknown-linux-gnu";
        };
      };
    in
    let qemu_shell = # OK for xv6
      hostPkgs.mkShell {
        hardeningDisable = [ "fortify" ];
        packages = with hostPkgs; [
          just
          clang
          python313
          python313Packages.distlib
          ninja
          pkg-config
          glib
          git
          ncurses
        ];
        shellHook = ''
          export CC=clang
        '';
      };
    in
    let xvisor_shell = # OK?
      hostPkgs.mkShell {
        packages = [
          hostPkgs.just
          hostPkgs.git
          hostPkgs.pkgsCross.riscv64-embedded.gcc
          hostPkgs.pkgsCross.riscv64-embedded.buildPackages.binutils
          hostPkgs.python313
        ];
      };
    in
    let linux_shell = # OK?
      let hostPkgs = import nixpkgs { system = host_system; }; in
      hostPkgs.mkShell {
        packages = [
          hostPkgs.just
          hostPkgs.bash
          hostPkgs.gnumake
          hostPkgs.binutils
          hostPkgs.bison
          hostPkgs.flex
          hostPkgs.bc

          riscv64Pkgs.binutils
          riscv64Pkgs.gcc
        ];
      };
    in
    let opensbi_shell = # OK?
      hostPkgs.mkShell {
        packages = with hostPkgs; [
          just
          pkgsCross.riscv64.buildPackages.gcc
          python313
        ];
      };
    in
    # let busybox_shell = # OK?
    #   hostPkgs.mkShell {
    #     packages = [
    #       riscvMuslPkgs.gcc
    #       riscvMuslPkgs.musl
    #       riscvMuslPkgs.pkgsStatic.glib
    #       riscvMuslPkgs.pkgsStatic.gcc
    #       hostPkgs.gnumake
    #       hostPkgs.just
    #       hostPkgs.cpio
    #       hostPkgs.dtc
    #     ];
    #   };
    # in
    let xv6_pkg =
      hostPkgs.stdenv.mkDerivation {
        name = "xv6-riscv-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "xv6-riscv";
          rev = "8662adf08ee541b54d4ec6b44881973d9f6f5e62";
          sha256 = "sha256-xDORtJ4piDz/sWSGPJtbdPUsfCqew9FFdlcxEfzaCy0=";
        };

        nativeBuildInputs = [
          hostPkgs.perl
          hostPkgs.gnumake

          riscv64Pkgs.binutils
          riscv64Pkgs.gcc
        ];

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
      hostPkgs.stdenv.mkDerivation {
        name = "linux-kernel-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "linux";
          rev = "b320789d6883cc00ac78ce83bccbfe7ed58afcf0";
          sha256 = "sha256-xuwSwpzFV/YVHrSqJMQRjoMPhFzufP999bLfPGzyXO4=";
          # sha256 = "0000000000000000000000000000000000000000000000000000";
        };

        nativeBuildInputs = [
          hostPkgs.bash
          hostPkgs.gnumake
          # pkgs.gcc
          hostPkgs.binutils
          hostPkgs.bison
          hostPkgs.flex
          hostPkgs.bc

          riscv64Pkgs.binutils
          riscv64Pkgs.gcc
        ];

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
        # The image is $out/linux/build/arch/riscv/boot/Image
      };
    in # end of let linux_pkg
    let opensbi_pkg =
      hostPkgs.stdenv.mkDerivation {
        name = "opensbi-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "opensbi";
          rev = "f6e15b228491c3df87e35124a2e10aba65084b62";
          sha256 = "sha256-8U3rThmhoAfz9QmHYi0PF5d8SLknGy0zIDYZ3a7WvOI=";
          # sha256 = "0000000000000000000000000000000000000000000000000000";
        };

        nativeBuildInputs = [
          hostPkgs.bash
          hostPkgs.python3
          # pkgs.compiledb

          hostPkgs.gnumake
          riscv64Pkgs.binutils
          riscv64Pkgs.gcc
        ];

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
    in # end of let opensbi_pkg
    let xvisor_pkg =
      hostPkgs.stdenv.mkDerivation {
        name = "xvisor-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "xvisor";
          rev = "03109cd214783a5fe1eda4a7538547239a3b0095";
          sha256 = "sha256-mLIIHgIRMaN87dvI36tTa2mTTzKbAqqETXQsqhJy2hg=";
        };

        nativeBuildInputs = [
          hostPkgs.gnumake
          hostPkgs.dtc
          hostPkgs.python3
          hostPkgs.pkgsCross.riscv64-embedded.gcc
          hostPkgs.pkgsCross.riscv64-embedded.buildPackages.binutils
        ];

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
          mkdir -p $out/xvisor/build/tests/riscv/virt64/basic
          cp build/vmm.bin $out/xvisor/build/vmm.bin
          cp build/tests/riscv/virt64/basic/firmware.bin \
            $out/xvisor/build/tests/riscv/virt64/basic/firmware.bin
        '';
      };
    in
    let busybox_pkgs =
      let riscv64MuslPkgs =
        import nixpkgs {
          system = host_system;
          crossSystem = {
            config = "riscv64-unknown-linux-musl";
          };
        };
      in
      riscv64MuslPkgs.stdenv.mkDerivation {
        name = "busybox-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "tokyo4j";
          repo = "busybox";
          rev = "b4cedd4c9ae0ea31986973b7b3e6956937aafa32";
          # sha256 = "0000000000000000000000000000000000000000000000000000";
          sha256 = "sha256-l01uowQ5vtmm8pbMAvx8L79ETx92XcHFDKyfO5zRPAw=";
        };

        nativeBuildInputs = [
          hostPkgs.cpio
          hostPkgs.dtc
          riscv64MuslPkgs.gnumake
          riscv64MuslPkgs.pkgsStatic.glib
          riscv64MuslPkgs.pkgsStatic.gcc
          riscv64MuslPkgs.gcc
          riscv64MuslPkgs.glib
          hostPkgs.gcc
        ];

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
        linux = linux_shell;
        xvisor = xvisor_shell;
        opensbi = opensbi_shell;
        # busybox = busybox_shell;
      };
      packages.x86_64-linux.default = hostPkgs.symlinkJoin {
        name = "combined";

        paths = [
          xv6_pkg
          linux_pkg
          opensbi_pkg
          xvisor_pkg
          busybox_pkgs
        ];
      };
      packages.x86_64-linux.xvisor = xvisor_pkg;
    };
  # end of let outputs
}
