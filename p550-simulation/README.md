# SiFive HiFive Premier P550 Simulation

This directory contains the implementation and experiments used to evaluate the performance characteristics of Page Success Exception on the SiFive HiFive Premier P550 platform.

Because the proposed hardware support is not implemented directly in the processor, the experiments use software techniques on the physical machine to simulate its expected performance effects. This evaluation complements the QEMU implementation by focusing on performance behavior under realistic hardware conditions.

Build scripts, experiment programs, measurement tools, results, and documentation specific to the P550 evaluation belong in this directory.

## Performance simulation

This implementation estimates application performance on a hypothetical P550 processor with Page Success Exception (PSE) support. PSE ensures that only memory pages for which access has been authorized can be installed in the TLB. Consequently, software running with PSE incurs no additional memory-access overhead while an address translation remains in the TLB. The additional firmware-processing cost is incurred only after a TLB miss.

The physical P550 does not implement PSE, so this experiment uses page faults as a proxy. PSE and page faults have similar timing in the address-translation path: both can raise an exception after the MMU encounters a TLB miss and performs a page-table walk. A real PSE would be handled by M-mode firmware, but this simulation handles the proxy page fault in the Linux kernel at S-mode to keep the implementation practical. By causing a page fault only after a TLB miss, while leaving TLB hits unaffected, the experiment approximates the performance characteristics of PSE.

The simulation creates this behavior by clearing the valid (`V`) bit—also referred to here as the present bit—in nearly all relevant page-table entries. A permitted address can remain cached as a valid TLB entry even while the corresponding page-table entry has its valid bit cleared. Access through that cached translation proceeds without additional overhead. Once the translation is evicted from the TLB, accessing the address again requires a page-table walk, observes the cleared valid bit, and raises a page fault.

For a user process, the simulation proceeds as follows:

1. When the process starts, the Linux kernel clears the valid bits in its page-table entries.
2. The process attempts a memory access. Because the required translation is not yet in the TLB, the access raises a page fault and transfers control to the kernel's page-fault handler.
3. The handler sets the valid bit in the page-table entry for the faulting address and resumes the process, allowing the translation to be installed in the TLB.
4. A later access whose translation is not in the TLB raises another page fault.
5. In addition to setting the valid bit for the new faulting address, the handler clears the valid bit that it set for the preceding fault, then resumes the process.

Steps 4 and 5 are repeated throughout execution. This keeps TLB hits on previously installed translations fast while using page-fault handling to model the additional work associated with PSE on TLB misses.

## Linux kernel implementation

The experimental kernel support is controlled by `CONFIG_RISCV_PSE_EXPERIMENT`, which is available only on 64-bit RISC-V systems with an MMU. The implementation adds the following components to `riscv-linux`:

- `include/uapi/linux/prctl.h` defines the `PR_RISCV_PSE_START`, `PR_RISCV_PSE_START_RANGES`, `PR_RISCV_PSE_GET_STATS`, and `PR_RISCV_PSE_STOP` operations, along with their userspace range and statistics structures.
- `kernel/sys.c` dispatches those `prctl()` operations to the RISC-V implementation.
- `arch/riscv/include/asm/pse.h` declares the architecture-internal interface.
- `arch/riscv/mm/pse.c` validates and pins the experimental memory ranges, saves their original PTEs, controls their valid bits, handles simulated PSE faults, collects statistics, and restores the mappings during shutdown.
- `arch/riscv/mm/fault.c` invokes the PSE handler before normal Linux page-fault processing for user-mode faults.
- The RISC-V `mm_context_t` contains a pointer to the PSE state associated with an address space. `exit_mmap()` tears down any active experiment when that address space exits.

At startup, the kernel accepts either one range through `PR_RISCV_PSE_START` or up to `PR_RISCV_PSE_MAX_RANGES` (64) ranges through `PR_RISCV_PSE_START_RANGES`. Every range must be page-aligned, nonempty, nonoverlapping, and contained within one readable and writable anonymous private VMA. All pages must already be backed by ordinary present, writable 4 KiB leaf PTEs. Shared mappings, hugetlb mappings, special PTEs, device mappings, `VM_PFNMAP`, and `VM_IO` are rejected. The aggregate experiment is limited to 2^20 pages.

The kernel pins every selected page with `pin_user_pages(..., FOLL_WRITE, ...)`, records its original PTE, clears the valid bit in each selected PTE, and flushes the address space from the TLB. On a subsequent load, store, or instruction page fault within a registered range, the handler:

1. verifies that the original PTE permits the faulting access;
2. sets the faulting PTE's valid bit;
3. executes an address-selective `sfence.vma` for the faulting address;
4. clears the valid bit of the page handled by the preceding simulated fault, without flushing that preceding address from the TLB; and
5. records the fault type and address in the experiment statistics.

Not flushing the preceding address is essential: its cached TLB translation remains usable without added overhead, but a later access faults after that translation has been evicted. `PR_RISCV_PSE_STOP`, or process address-space teardown, restores valid PTEs, performs an address-space-wide TLB flush, unpins the pages, and frees the experiment state.

This is research instrumentation rather than a general-purpose memory-management feature. The kernel verifies at experiment startup that the process has one thread and is restricted to one CPU. The process must remain on that CPU for the entire experiment; faults on another CPU are not handled as simulated PSE faults. To avoid conflicts with saved PTEs and cached translations, do not create threads, change CPU affinity, or perform address-space-changing operations such as `fork()`, `clone()`, `execve()`, `mmap()`, `munmap()`, `mremap()`, `mprotect()`, `brk()`, `mbind()`, or `madvise()` while an experiment is active. The local kernel build disables NUMA balancing, transparent huge pages, and KSM. Swap should also be disabled for the experiment, although the selected pages are pinned against swap, reclaim, and migration while registered.

## Running a PSE experiment

An experimental process should perform the following steps:

1. Restrict itself to exactly one CPU, for example with `sched_setaffinity()`.
2. Allocate one or more page-aligned, writable anonymous private mappings. Keep each registered range within a single VMA.
3. Touch every page before starting the experiment so that each page has a present 4 KiB PTE. Do not register guard pages, `PROT_NONE` pages, or unmapped portions of an allocation.
4. Start instrumentation with one of the following interfaces. All currently defined flags must be zero.

   ```c
   prctl(PR_RISCV_PSE_START, start, length, 0UL, 0UL);

   struct pr_riscv_pse_range ranges[] = {
       { .start = start_a, .length = length_a },
       { .start = start_b, .length = length_b },
   };
   prctl(PR_RISCV_PSE_START_RANGES, ranges,
         sizeof(ranges) / sizeof(ranges[0]), 0UL, 0UL);
   ```

5. Run the single-threaded workload without changing its affinity or address-space layout.
6. Read aggregate results while the experiment is active. The v2 structure includes the range count and total registered length; fault counters distinguish load, store, and instruction faults.

   ```c
   struct pr_riscv_pse_stats_v2 stats;

   prctl(PR_RISCV_PSE_GET_STATS, &stats, sizeof(stats), 0UL, 0UL);
   ```

7. Stop the experiment before releasing or modifying its mappings.

   ```c
   prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL);
   ```

Each `prctl()` returns zero on success and `-1` in userspace on failure, with `errno` reporting the kernel error. A process may have only one active PSE experiment. Statistics from the v1 structure remain supported; for a multi-range run, its `start` field is zero and its length and counters are aggregate values.

## Experiment programs

The repository contains two functional tests and one measurement-oriented microbenchmark. Build the local RISC-V binaries with:

```sh
make build-local-pse-programs
```

This produces statically linked `pse_phase1`, `pse_multirange`, and `pse_microbench` executables that can be copied to the P550. `make build-local-all` builds these programs together with the local Linux kernel. The reproducible `make build-all` output instead places the programs under `result/bin/`.

### `pse_phase1`

`pse_phase1.c` is a basic functional test of the single-range PSE interface. It pins itself to its current CPU, allocates one anonymous private mapping, registers the entire mapping with `PR_RISCV_PSE_START`, and accesses the first byte of every 4 KiB page. It then revisits the pages to exercise translations after filling more entries than a typical L1 TLB, reads the PSE statistics, stops the experiment, and verifies that at least one simulated PSE fault was recorded per page.

The optional arguments select the number of pages and traversals; their defaults are 4096 pages and two traversals:

```sh
./pse_phase1 [pages [traversals]]
```

This program is intended only to check that single-range registration, fault handling, statistics collection, and cleanup work. It is not a performance benchmark.

### `pse_multirange`

`pse_multirange.c` is a functional test of `PR_RISCV_PSE_START_RANGES`. It pins itself to its current CPU, creates and populates two anonymous private mappings, registers both ranges in one experiment, and alternates accesses between them. Alternating the mappings checks that the kernel's preceding-PTE tracking works across range boundaries. The program verifies the reported range count, total length, page count, and minimum expected number of faults before stopping the experiment.

The optional argument selects the number of pages in each of the two mappings; the default is 64:

```sh
./pse_multirange [pages-per-range]
```

Like `pse_phase1`, this is a correctness test rather than a performance benchmark.

### `pse_microbench`

`pse_microbench.c` is the primary microbenchmark for measuring the performance effects of the simulated Page Success Exception. Its command line is:

```sh
./pse_microbench <normal|custom> [pages] [accesses] \
  [sequential|sequential64|random] [seed] [write|read]
```

The defaults are 4096 pages, one access per page, the `sequential` pattern, seed 1, and `write`. The process pins itself to its current CPU, allocates an anonymous private mapping, and writes to every page before measurement so that demand allocation and copy-on-write faults are excluded from the timed region.

The two modes prepare address translation differently:

- `normal` changes the mapping from read/write to `PROT_NONE` and back with `mprotect()`. This invalidates cached translations while leaving ordinary present PTEs, so subsequent misses use the normal page-table walk.
- `custom` registers the mapping with `PR_RISCV_PSE_START`, so misses encounter deliberately invalid PTEs and are handled by the experimental PSE page-fault path.

The access patterns are:

- `sequential`: access the first byte of each 4 KiB page in order, wrapping at the end of the mapping.
- `sequential64`: access one byte every 64 bytes in order, wrapping at the end of the mapping.
- `random`: access the first byte of pseudorandomly selected 64-byte regions. The complete index sequence is generated before measurement, and using the same nonzero seed produces the same sequence for normal and custom runs. A seed of zero is internally replaced with 1.

Each pattern supports `write` and `read`. Reads are accumulated into `checksum` so that the compiler cannot remove them. The measured region contains the access loop but excludes allocation, initial page population, random-index generation, PSE setup, and statistics retrieval.

The benchmark reports both elapsed time from `CLOCK_MONOTONIC_RAW` and cycles from the RISC-V `cycle` counter. It creates a `PERF_COUNT_HW_CPU_CYCLES` event without excluding kernel execution, maps the perf metadata page, and reads `rdcycle` directly. The custom-mode cycle count therefore includes time spent in the S-mode PSE fault handler. Systems that restrict performance counters require the benchmark to run as root. Each run prints one whitespace-separated line of `key=value` fields containing the mode, operation, pattern, memory size, access count, seed, total and average time, total and average cycles, CPU, PSE fault counters, and checksum.

For example, the following commands compare one million random reads over 4096 pages with the same access sequence:

```sh
sudo taskset -c 0 ./pse_microbench normal 4096 1000000 random 1 read
sudo taskset -c 0 ./pse_microbench custom 4096 1000000 random 1 read
```

The reported averages include loop and address-calculation overhead, memory-system effects, interrupts, and the fixed timing calls in addition to page-table walks or PSE fault handling. `normal` does not count hardware TLB misses directly, and the custom `faults` value counts faults handled by this experimental mechanism rather than every hardware TLB miss.

## Repeated microbenchmark runs

`run_microbenchmark.sh` repeatedly invokes `pse_microbench` and writes the parsed results to CSV. It must be run as root. By default it tests 64, 128, 256, 512, 1024, 2048, and 4096 pages. For each size it performs 30 trials of both normal and custom mode with one million accesses, producing 420 measurements in total. Odd-numbered trials run normal before custom, while even-numbered trials reverse that order to reduce ordering bias. Every process is restricted to the CPU selected with `taskset`.

Run the default sequential-write experiment with:

```sh
sudo ./run_microbenchmark.sh
```

The runner is configured through environment variables:

- `TRIALS` sets the number of paired trials per page count; the default is 30.
- `ACCESSES` sets the accesses per process; the default is 1,000,000.
- `CPU` selects the CPU used by `taskset`; the default is 0.
- `PATTERN` selects `sequential`, `sequential64`, or `random`; the default is `sequential`.
- `SEED` selects the random sequence; the default is 1.
- `OPERATION` selects `write` or `read`; the default is `write`.
- `OUTPUT` selects the CSV path; the default is `microbenchmark-results.csv`.

For example, this runs 30 paired random-read trials for each memory size:

```sh
sudo env \
  TRIALS=30 \
  ACCESSES=1000000 \
  CPU=0 \
  PATTERN=random \
  SEED=1 \
  OPERATION=read \
  OUTPUT=random-read-results.csv \
  ./run_microbenchmark.sh
```

The CSV contains the trial and page count followed by the fields emitted by `pse_microbench`: memory size, mode, operation, pattern, seed, access count, total and average nanoseconds, total and average cycles, CPU, total/load/store fault counts, and checksum. Avoid running other CPU-intensive work on the selected CPU while collecting results.
