# Page Success Exception Demo

- QEMU: https://github.com/tokyo4j/qemu/tree/page-success-exception
- xv6: https://github.com/tokyo4j/xv6-riscv/tree/page-success-exception

## Prerequisites

- [Nix](https://nixos.org/download/) must be installed. The Makefile enables the `nix-command` and `flakes` experimental features when invoking Nix.
- `make` is required to run the build and launch commands.
- `sudo` access is required when creating the device nodes in the BusyBox initramfs.

## Building

```sh
git clone https://github.com/tokyo4j/page-success-exception
cd page-success-exception
make build-all
```

`make build-all` builds QEMU, xv6, Linux, OpenSBI, BusyBox, and XVisor, then generates the BusyBox and XVisor initramfs images.

### Local development environments

The flake provides a development shell for each component. Each shell uses the same build dependencies as the corresponding Nix package, so a locally modified submodule can be built in an environment similar to the package build.

First, initialize all local-development submodules with Git provided by Nix:

```sh
make setup-local-pkgs
```

To initialize only one component, use `make setup-xv6`, `make setup-linux`, `make setup-xvisor`, `make setup-busybox`, or `make setup-opensbi`. The local build targets run their corresponding setup target automatically, so the host system's Git command is not used.

Enter the appropriate development shell from the repository root, then move into the component's source directory:

| Component | Development shell | Source directory |
| --- | --- | --- |
| xv6 | `nix develop .#xv6` | `xv6-riscv/` |
| Linux | `nix develop .#linux` | `linux/` |
| XVisor | `nix develop .#xvisor` | `xvisor/` |
| BusyBox | `nix develop .#busybox` | `busybox/` |
| OpenSBI | `nix develop .#opensbi` | `opensbi/` |

For example, to work on xv6:

```sh
nix develop .#xv6
cd xv6-riscv
make fs.img kernel/kernel
```

The Linux, XVisor, BusyBox, and OpenSBI shells also set the cross-compilation environment variables used by their Nix package builds, such as `ARCH`, `CROSS_COMPILE`, `PLATFORM`, and `FW_TEXT_START` where applicable. Changes made inside the submodule remain in the local checkout and can be rebuilt repeatedly without changing the source revision in `flake.nix`.

The Makefile provides targets that build the local submodule sources in these development shells and replace the corresponding artifacts under `build/`:

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

Set the Makefile variable `QEMU_DEBUG` to `1` when configuring QEMU to enable its debug build options:

```sh
make setup-qemu QEMU_DEBUG=1
make build-qemu
```

When `QEMU_DEBUG` is omitted, QEMU is built without `--enable-debug`. `make build-all` always uses this non-debug configuration.

## Running

### Booting xv6

```sh
make run-xv6
```

### Booting Linux

```sh
make run-linux
```

### Booting XVisor

```sh
make run-xvisor
```

## Output

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
