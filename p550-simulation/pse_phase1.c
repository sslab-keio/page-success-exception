// SPDX-License-Identifier: GPL-2.0-only
#define _GNU_SOURCE

#include <errno.h>
#include <inttypes.h>
#include <sched.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <unistd.h>

#ifndef PR_RISCV_PSE_START
#define PR_RISCV_PSE_START		0x53504501
#define PR_RISCV_PSE_STOP		0x53504502
#define PR_RISCV_PSE_GET_STATS		0x53504503
#endif

struct pr_riscv_pse_stats {
	uint64_t start;
	uint64_t length;
	uint64_t nr_pages;
	uint64_t fault_count;
	uint64_t load_fault_count;
	uint64_t store_fault_count;
	uint64_t instruction_fault_count;
	uint64_t last_fault_address;
	uint32_t cpu;
	uint32_t active;
};

static int pin_to_current_cpu(void)
{
	cpu_set_t set;
	int cpu = sched_getcpu();

	if (cpu < 0)
		return -1;

	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	return sched_setaffinity(0, sizeof(set), &set);
}

int main(int argc, char **argv)
{
	struct pr_riscv_pse_stats stats;
	size_t page_size = sysconf(_SC_PAGESIZE);
	size_t nr_pages = 4096;
	size_t nr_traversals = 2;
	size_t length;
	volatile unsigned char *mapping;
	uint64_t sum = 0;
	size_t traversal;
	size_t i;

	if (argc >= 2)
		nr_pages = strtoul(argv[1], NULL, 0);
	if (argc == 3)
		nr_traversals = strtoul(argv[2], NULL, 0);
	if (argc > 3 || !nr_pages || nr_pages > SIZE_MAX / page_size ||
	    !nr_traversals) {
		fprintf(stderr, "usage: %s [pages [traversals]]\n", argv[0]);
		return EXIT_FAILURE;
	}
	length = nr_pages * page_size;

	if (pin_to_current_cpu()) {
		perror("sched_setaffinity");
		return EXIT_FAILURE;
	}

	mapping = mmap(NULL, length, PROT_READ | PROT_WRITE,
		       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (mapping == MAP_FAILED) {
		perror("mmap");
		return EXIT_FAILURE;
	}

	if (prctl(PR_RISCV_PSE_START, (unsigned long)mapping, length, 0UL, 0UL)) {
		perror("PR_RISCV_PSE_START");
		munmap((void *)mapping, length);
		return EXIT_FAILURE;
	}

	for (i = 0; i < nr_pages; i++) {
		mapping[i * page_size] = (unsigned char)i;
		sum += mapping[i * page_size];
	}

	/* Revisit pages after filling more TLB entries than a typical L1 TLB. */
	for (traversal = 1; traversal < nr_traversals; traversal++)
		for (i = 0; i < nr_pages; i++)
			sum += mapping[i * page_size];

	memset(&stats, 0, sizeof(stats));
	if (prctl(PR_RISCV_PSE_GET_STATS, &stats, sizeof(stats), 0UL, 0UL)) {
		perror("PR_RISCV_PSE_GET_STATS");
		prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL);
		munmap((void *)mapping, length);
		return EXIT_FAILURE;
	}

	printf("range=%#" PRIx64 "+%#" PRIx64
	       " pages=%" PRIu64 " traversals=%zu faults=%" PRIu64
	       " load=%" PRIu64 " store=%" PRIu64
	       " instruction=%" PRIu64 " last=%#" PRIx64
	       " cpu=%" PRIu32 " sum=%" PRIu64 "\n",
	       stats.start, stats.length, stats.nr_pages, nr_traversals,
	       stats.fault_count,
	       stats.load_fault_count, stats.store_fault_count,
	       stats.instruction_fault_count, stats.last_fault_address,
	       stats.cpu, sum);

	if (prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL)) {
		perror("PR_RISCV_PSE_STOP");
		munmap((void *)mapping, length);
		return EXIT_FAILURE;
	}

	if (stats.fault_count < nr_pages) {
		fprintf(stderr, "too few faults: expected at least %zu\n", nr_pages);
		munmap((void *)mapping, length);
		return EXIT_FAILURE;
	}

	if (munmap((void *)mapping, length)) {
		perror("munmap");
		return EXIT_FAILURE;
	}
	return EXIT_SUCCESS;
}
