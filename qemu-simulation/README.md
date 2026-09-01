# QEMU Simulation

This directory contains the implementation and evaluation of the Page Success Exception mechanism using QEMU.

The QEMU-based environment is used to implement the proposed hardware support, integrate it with the relevant system software, and evaluate whether the mechanism is feasible. It provides a controllable platform for validating the behavior of Page Success Exception before considering a hardware implementation.

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled

## Reproducible artifacts

```sh
nix build .
```

This builds all finished artifacts: QEMU, xv6, Linux, OpenSBI, BusyBox, XVisor, and the Linux and XVisor initramfs images. The component repositories, revisions, and source hashes are pinned in `flake.nix`; Git submodules do not need to be initialized.

After the build, launch each environment with one command:

```sh
nix run .#xv6
nix run .#linux
nix run .#xvisor
```

The commands boot xv6, Linux, and XVisor respectively on the PSE-enabled QEMU. Detailed execution examples are shown below.

To build only the PSE-enabled RISC-V QEMU:

```sh
nix build .#qemu
```

The resulting executable is `result/bin/qemu-system-riscv64`. It can also be invoked directly through the flake:

```sh
nix run .#qemu -- --version
```

The `qemu` package is the optimized release build and is stripped during the Nix fixup phase. To build QEMU with its debug configuration and retain debug symbols, use:

```sh
nix build .#qemu-debug
```

### Building the initramfs images

Build the BusyBox initramfs used to boot Linux with:

```sh
nix build .#linux-initramfs
```

The result is `result/initramfs.cpio.gz`. The build creates the required device-node metadata without `sudo`.

Build the XVisor initramfs with:

```sh
nix build .#xvisor-initramfs
```

The result is `result/xvisor-initrd.cpio`. It contains the XVisor boot files, Linux kernel, device trees, guest firmware, and the BusyBox root filesystem produced by `linux-initramfs`.

## Running

### Booting xv6

```sh
nix run .#xv6
```

This runs the xv6 artifacts built by Nix on the PSE-enabled QEMU package directly; it does not enter a nested development shell. The filesystem uses a temporary QEMU snapshot because Nix store artifacts are immutable.

To run xv6 with the debug QEMU package instead of the release build, use:

```sh
nix run .#xv6 -- --debug
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
nix run .#linux
```

Use `nix run .#linux -- --debug` to boot it with the debug QEMU package.

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
nix run .#xvisor
```

Use `nix run .#xvisor -- --debug` to boot it with the debug QEMU package.

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
