# Page Success Exception

Page success exception (PSE) is a lightweight hardware mechanism for prototyping memory protection schemes. It enables system developers to propose and test new memory protection mechanisms without modifying hardware or hardware simulators. A memory protection mechanism can be implemented as a software module. The proposed hardware raises an exception, named a page success exception, after successful address translation on a TLB miss, allowing the software module to intercept the translation result and enforce access-control policies. The software module can be implemented as a PSE exception handler.

This project designs hardware support for PSE on the RISC-V architecture. The proposed hardware raises PSEs to an M-mode handler. The M-mode software can inspect address translations using the virtual address, physical address, and page table entries provided through CSRs. To approve or reject a translation, the software can decide whether to fill the corresponding TLB entry by configuring CSRs.

Currently, this project implements the hardware support in QEMU. This repository demonstrates a prototype of an Intel SGX-like enclave built using PSE. The enclave runs on the xv6 operating system, and the PSE handler is implemented in M-mode software as part of xv6. Support for enclaves on Linux + OpenSBI and confidential VMs on a hypervisor is still under development.

## Implementations

- [`qemu-simulation/`](qemu-simulation/) contains the QEMU implementation of the mechanism and its feasibility evaluation.
- [`p550-simulation/`](p550-simulation/) contains the performance-characteristic evaluation conducted with the SiFive HiFive Premier P550 platform.
