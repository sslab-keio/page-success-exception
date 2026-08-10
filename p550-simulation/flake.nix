{
  description = "RISC-V Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { nixpkgs, ... }:
    let host_system = "x86_64-linux"; in
    let hostPkgs = import nixpkgs { system = host_system; }; in
    let linux_pkg =
      hostPkgs.stdenv.mkDerivation {
        name = "linux-kernel-pse";

        src = hostPkgs.fetchFromGitHub {
          owner = "terufumi-hata";
          repo = "riscv-linux";
          rev = "48419e79564f3b48d42f8dba500f5ed5ea30fd66";
          hash = "sha256-nV6OdD686MF2Zq/a+76fYHfoC0FKwVj75KtWQigfoWM=";
        };

        kernelConfig = ./p550.config;

        nativeBuildInputs = [
          hostPkgs.bash
          hostPkgs.perl
          hostPkgs.gnumake
          hostPkgs.binutils
          hostPkgs.bison
          hostPkgs.flex
          hostPkgs.bc
          hostPkgs.cpio
          hostPkgs.pkg-config
          hostPkgs.openssl.dev
          hostPkgs.openssl.out
          hostPkgs.zstd
          hostPkgs.kmod
          hostPkgs.dpkg
          hostPkgs.pkgsCross.riscv64.buildPackages.gcc
          hostPkgs.pkgsCross.riscv64.buildPackages.binutils
        ];

        configurePhase = ''
          makeFlagsArray+=(
            "ARCH=riscv"
            "CROSS_COMPILE=riscv64-unknown-linux-gnu-"
          )

          export O=$PWD/build
          mkdir -p $PWD/$O

          mkdir -p $O/scripts/
          cp "$kernelConfig" $O/.config

          cp $src/scripts/config $O/scripts/config
          substituteInPlace $O/scripts/config --replace-fail \
            '#!/usr/bin/env bash' "#!$SHELL"

          $O/scripts/config --file $O/.config \
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

          make -C $src \
            O=$O \
            "''${makeFlagsArray[@]}" \
            olddefconfig
        '';

        buildPhase = ''
          make -C $src \
            O=$O \
            "''${makeFlagsArray[@]}" \
            -j$(nproc) \
            Image modules dtbs
        '';

        installPhase =''
          kernelRelease="$(
            cat "$O/include/config/kernel.release"
          )"

          mkdir -p \
            $out/linux/boot \
            $out/linux/lib/modules \
            $out/linux/share/p550-kernel

          cp -r $O/arch/riscv/boot/Image $out/linux/boot/Image-$kernelRelease
          ln -s Image-$kernelRelease $out/linux/boot/vmlinuz-$kernelRelease
          cp -r $O/.config               $out/linux/boot/config-$kernelRelease
          cp -r $O/System.map            $out/linux/boot/System.map-$kernelRelease

          find $O/arch/riscv/boot/dts \
            -type f -name '*.dtb' \
            -exec cp --parents '{}' "$out/linux/share/p550-kernel/" \;

          make -C $src \
            O=$O \
            "''${makeFlagsArray[@]}" \
            INSTALL_MOD_PATH="$out/linux" \
            modules_install

          rm -f \
            "$out/linux/lib/modules/$kernelRelease/build" \
            "$out/linux/lib/modules/$kernelRelease/source"

          make -C $src \
            O=$O \
            "''${makeFlagsArray[@]}" \
            INSTALL_DTBS_PATH="$out/linux/boot/dtbs/$kernelRelease" \
            dtbs_install

          echo "$kernelRelease" > "$out/linux/kernel-release"

          debRoot="$TMPDIR/linux-image-p550-deb"
          mkdir -p "$debRoot/DEBIAN"
          cp -a "$out/linux/boot" "$debRoot/boot"
          mkdir -p "$debRoot/lib"
          cp -a "$out/linux/lib/modules" "$debRoot/lib/modules"
          mkdir -p "$debRoot/usr/lib/linux-image-$kernelRelease"
          cp -a \
            "$out/linux/boot/dtbs/$kernelRelease/." \
            "$debRoot/usr/lib/linux-image-$kernelRelease/"

          cat > "$debRoot/DEBIAN/control" <<EOF
          Package: linux-image-p550-custom
          Version: $kernelRelease
          Architecture: riscv64
          Maintainer: PSE kernel developers
          Section: kernel
          Priority: optional
          Description: Custom Linux kernel for the SiFive Premier P550
           RISC-V Linux kernel image, device trees, System.map, configuration,
           and loadable modules built reproducibly by the PSE Nix flake.
          EOF

          dpkg-deb \
            --root-owner-group \
            --build "$debRoot" \
            "$out/linux-image-$kernelRelease-riscv64.deb"
        '';
        # The image is $out/linux/build/arch/riscv/boot/Image
      };
    in
    {
      packages.x86_64-linux.default = linux_pkg;
      packages.x86_64-linux.linux = linux_pkg;
    };
  # end of let outputs
}
