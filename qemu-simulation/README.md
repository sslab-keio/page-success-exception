# QEMU Simulation

This directory contains the implementation and evaluation of the Page Success Exception mechanism using QEMU.

The QEMU-based environment is used to implement the proposed hardware support, integrate it with the relevant system software, and evaluate whether the mechanism is feasible. It provides a controllable platform for validating the behavior of Page Success Exception before considering a hardware implementation.

## Build model

This repository uses two different source workflows to balance highly reproducible Nix builds with convenient local development.

The outputs of `nix build` are the finished, reproducible artifacts. The repositories, commit IDs, and source hashes used to produce them are specified directly in `flake.nix` with `pkgs.fetchFromGitHub`. If you only want to build and run the project without modifying its component source code, use the Nix build workflow. You do not need to initialize the xv6, Linux, OpenSBI, BusyBox, or XVisor submodules.

The Git submodules provide writable source trees for development. Initialize the relevant submodule when you want to modify xv6, Linux, OpenSBI, BusyBox, or XVisor and test the changes locally. The development shells defined in `flake.nix` provide the same build dependencies used by the corresponding Nix package, so `nix develop` supplies the tools required to build each local source tree.

After a local change is ready to become part of the reproducible build, commit it in the component repository and update its commit ID and source hash in `flake.nix`. Until those values are updated, `nix build` continues to build the pinned source rather than the locally modified submodule.

QEMU is the exception: QEMU itself is built from its Git submodule inside the `nix develop .#qemu` shell. Its source is not fetched by a `pkgs.fetchFromGitHub` derivation. The Makefile handles this workflow through `make setup-qemu` and `make build-qemu`.

The Makefile provides a simple interface for these Nix workflows, so most users do not need to invoke the underlying Nix commands directly. Run `make build-all` to build all finished artifacts from their pinned sources. For local development, build QEMU first with `make setup-qemu` and `make build-qemu`, then use `make build-local-all` to build the other local source trees and regenerate the initramfs images used by the run commands.

## Prerequisites

- [Nix](https://nixos.org/download/) must be installed. The Makefile enables the `nix-command` and `flakes` experimental features when invoking Nix.
- `make` is required to run the build and launch commands.
- `sudo` access is required when creating the device nodes in the BusyBox initramfs.

## Reproducible artifacts

```sh
make build-all
```

`make build-all` builds all finished artifacts: QEMU, xv6, Linux, OpenSBI, BusyBox, and XVisor. It then generates the BusyBox and XVisor initramfs images required by the run commands.

The xv6, Linux, OpenSBI, BusyBox, and XVisor artifacts are produced by `nix build` from the repositories and revisions pinned in `flake.nix`. This workflow does not download or initialize their Git submodules. QEMU remains the exception described above and is built from its submodule in the Nix development shell.

## Local development environments

The flake provides a development shell for each component. Each shell uses the same build dependencies as the corresponding Nix package, so a locally modified submodule can be built in an environment similar to the package build.

For the usual local-development workflow, run:

```sh
make setup-qemu
make build-qemu
make build-local-all
```

The first two commands initialize, configure, and build QEMU. `make build-local-all` does not build QEMU; it initializes the xv6, Linux, OpenSBI, BusyBox, and XVisor submodules with Git provided by Nix, builds those five local source trees in their Nix development shells, replaces the corresponding artifacts under `build/`, and regenerates the BusyBox and XVisor initramfs images. The local build targets run their corresponding setup targets automatically, so the host system's Git command is not used.

To initialize the submodules without building them, use `make setup-local-pkgs`. To initialize only one component, use `make setup-xv6`, `make setup-linux`, `make setup-xvisor`, `make setup-busybox`, or `make setup-opensbi`.

The Makefile provides convenient targets for building individual local submodules. Each target automatically uses the appropriate Nix development shell and replaces the corresponding artifact under `build/`, so you normally do not need to enter the shell manually:

```sh
make build-local-xv6
make build-local-linux
make build-local-opensbi
make build-local-busybox
make build-local-xvisor
```

Use `make build-local-pkgs` to run all five targets. Use `make build-local-all` to also regenerate the BusyBox and XVisor initramfs images. Like `make build-all`, initramfs generation may require `sudo` to create device nodes.

After a local build, the existing `make run-xv6`, `make run-linux`, and `make run-xvisor` commands use the replaced artifacts from `build/`. Running `make build-pkgs` again replaces them with artifacts produced by `nix build`.

### Building QEMU for debugging

QEMU must be configured with `--enable-debug` when it is needed for debugging. Set the Makefile variable `QEMU_DEBUG` to `1` when running the setup command, then build QEMU:

```sh
make setup-qemu QEMU_DEBUG=1
make build-qemu
```

The setup target adds `--enable-debug` to QEMU's configure options when `QEMU_DEBUG=1` is specified. When `QEMU_DEBUG` is omitted, QEMU is built without `--enable-debug`. `make build-all` always uses this non-debug configuration.

## Running

### Booting xv6

```sh
make run-xv6
```

After xv6 boots, run `etest` at the shell prompt. The expected output is:

```sh
xv6 kernel is booting

init: starting sh
$ etest
[ECREATE] id:1
start=1000, end=4000
enclave_size=3000
[EADD] id:1 va:1000->pa:87f2a000
[EADD] id:1 va:2000->pa:87f29000
[EADD] id:1 va:3000->pa:87f28000
[EENTER] id:1 pc:1000
[EEXIT]
result=213D0
```

### Booting Linux

```sh
make run-linux
```

A successful boot reaches the BusyBox shell prompt and produces output similar to:

```text
[    1.419190] ALSA device list:
[    1.419381]   No soundcards found.
[    1.463544] Freeing unused kernel image (initmem) memory: 2388K
[    1.464583] Run /init as init process
~ # ls
bin                init               proc               tmp
dev                initramfs.cpio.gz  root               usr
etc                linuxrc            sbin
home               mnt                sys
~ #
```

### Booting XVisor

```sh
make run-xvisor
```

XVisor creates and starts `guest0`, then binds the terminal to the guest's serial console. The expected output ends at the guest firmware's `basic#` prompt:

```text
Mounted initrd using cpio at /
INIT: bootcmd:  vfs run /boot.xscript
Created default shared memory
guest0: Created
guest0: Parsing /images/riscv/virt64/nor_flash.list
guest0: Loading 0x0000000000000000 with file ./firmware.bin
guest0: Loaded 0x0000000000000000 with 77996 bytes
guest0: Loading 0x00000000000FF000 with file ./cmdlist
guest0: Loaded 0x00000000000FF000 with 169 bytes
guest0: Loading 0x0000000000100000 with file ./Image
guest0: Loaded 0x0000000000100000 with 27374080 bytes
guest0: Loading 0x0000000001F00000 with file ./virt64.dtb
guest0: Loaded 0x0000000001F00000 with 2122 bytes
guest0: Loading 0x0000000002000000 with file ./rootfs.img
guest0: Loaded 0x0000000002000000 with 839402 bytes
INIT: bootcmd:  guest kick guest0
guest0: Kicked
INIT: bootcmd:  vserial bind guest0/uart0
[guest0/uart0] RISC-V SBI specification v2.0 detected
[guest0/uart0] RISC-V SBI implementation ID=0x2 Version=0x3002
[guest0/uart0]
[guest0/uart0] RISC-V Virt64 Basic Firmware
[guest0/uart0]
[guest0/uart0] autoboot: disabled
[guest0/uart0]
[guest0/uart0] basic#
```

At the `basic#` prompt, run the XVisor guest firmware command `autoexec` to boot Linux. A successful boot reaches the BusyBox shell prompt and produces output similar to:

```text
[guest0/uart0] basic# autoexec
[... output omitted ...]
[guest0/uart0] [    4.950490] ALSA device list:
[guest0/uart0] [    4.960917]   No soundcards found.
[guest0/uart0] [    5.038241] Freeing unused kernel image (initmem) memory: 2388K
[guest0/uart0] [    5.052926] Run /init as init process
[guest0/uart0] ~ # ls
[guest0/uart0] bin                init               proc               tmp
[guest0/uart0] dev                initramfs.cpio.gz  root               usr
[guest0/uart0] etc                linuxrc            sbin
[guest0/uart0] home               mnt                sys
[guest0/uart0] ~ #
```

## Hardware Specification

- Page success exception: An exception raised in M-mode after a page table walk triggered by a TLB miss succeeds
  - The M-mode exception handler can approve or reject the address translation
    - If the handler approves the address translation and executes the `mret` instruction, the TLB entry is populated and execution resumes in S-mode/U-mode
    - If the handler rejects the address translation and executes the `mret` instruction, another page success exception is raised (TBD)
- Two CSRs are added:
  - `mpsec`: Page success exception control register
    - Writing `1` enables page success exceptions
    - Writing `2` disables page success exceptions
    - Writing `4` approves the address translation
    - Writing `8` rejects the address translation
  - `mpsepa`: Page success exception physical address register
    - Contains the physical address produced by the address translation that triggered the page success exception
    - Note: Refer to `mtval` for the virtual address
- Three exceptions are added:
  - _Page instruction fetch success exception_ (mcause=0x18)
  - _Page load success exception_ (mcause=0x19)
  - _Page store success exception_ (mcause=0x1a)

## xv6 Implementation

### Memory Tracking Table (`kernel/firmware/firmware.c:strcut mtte`)

```c
struct mtte {
  uint64 va;
  uint8 id;
};
```

Like the RMP in AMD SEV-SNP, this table stores the enclave ID and virtual address for every physical memory page.

### During Boot (`kernel/firmware/firmware.c:start()`)

- Enable page success exceptions
- Set the interrupt vector for M-mode

### Exception Handler (`kernel/firmware/firmware.c:firmware_trap()`)

- Page success exceptions: Restrict memory access by consulting the MTT
  - Deny access to the firmware
  - Deny instruction fetches from the normal OS/app while executing in an enclave
  - For every memory access from an enclave, verify that the virtual address and enclave ID match the MTT entry
  - Deny access to enclave memory from the normal OS/app
- Illegal instruction exceptions: Execute the `ECREATE`, `EADD`, `EENTER`, or `EEXIT` instruction according to the contents of the `a0` register
  - `ECREATE()`:
    - Create an enclave execution context and return the enclave ID
    - Executed from S-mode
  - `EADD(id, epc_pa, va)`:
    - Assign a regular physical memory page to an enclave
    - Executed from S-mode
    - `id`: Enclave ID
    - `epc_pa`: Address of the physical memory page to assign
    - `va`: Virtual address to which the page is mapped
  - `EENTER(id, pc)`:
    - Start enclave execution
    - Executed from U-mode
    - `id`: ID of the enclave to execute
    - `pc`: Virtual address of the code to jump to
  - `EEXIT()`
    - End enclave execution and return to the normal application
    - Executed from U-mode

### System Calls (`kernel/enclave.c`)

- `u64 ecreate(void)`
- `void eadd(enclave_id, va)`
  - Assign the physical page mapped at `va` in the process to the enclave using the `EADD` instruction

### Test Application (`user/etest.c`)

- Create an enclave using the `ecreate()` system call
- Allocate the program and stack space to be used by the enclave using the `eadd()` system call
- Jump to `enclave_entry()` with the `EENTER` instruction and start enclave execution
- `enclave_entry()` switches to the enclave stack and then jumps to `enclave_main()`
- `enclave_main()` calculates the Fibonacci sequence and stores its 32nd element in `fib_result`
- `enclave_entry()` executes the `EEXIT` instruction and returns to the normal application
- Print the contents of `fib_result`
