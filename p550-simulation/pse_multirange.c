// SPDX-License-Identifier: GPL-2.0-only
#define _GNU_SOURCE

#include <inttypes.h>
#include <sched.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <unistd.h>

#ifndef PR_RISCV_PSE_START_RANGES
#define PR_RISCV_PSE_STOP		0x53504502
#define PR_RISCV_PSE_GET_STATS		0x53504503
#define PR_RISCV_PSE_START_RANGES	0x53504504
#endif

struct pr_riscv_pse_range {
	uint64_t start;
	uint64_t length;
};

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

struct pr_riscv_pse_stats_v2 {
	struct pr_riscv_pse_stats v1;
	uint64_t nr_ranges;
	uint64_t total_length;
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
	struct pr_riscv_pse_stats_v2 stats = {};
	struct pr_riscv_pse_range ranges[2];
	size_t page_size = sysconf(_SC_PAGESIZE);
	size_t nr_pages = 64;
	size_t length;
	volatile unsigned char *first = MAP_FAILED;
	volatile unsigned char *second = MAP_FAILED;
	uint64_t sum = 0;
	size_t i;
	int status = EXIT_FAILURE;
	bool active = false;

	if (argc == 2)
		nr_pages = strtoul(argv[1], NULL, 0);
	if (!nr_pages || nr_pages > SIZE_MAX / page_size) {
		fprintf(stderr, "invalid page count\n");
		return EXIT_FAILURE;
	}
	length = nr_pages * page_size;

	if (pin_to_current_cpu()) {
		perror("sched_setaffinity");
		return EXIT_FAILURE;
	}

	first = mmap(NULL, length, PROT_READ | PROT_WRITE,
		     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	second = mmap(NULL, length, PROT_READ | PROT_WRITE,
		      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (first == MAP_FAILED || second == MAP_FAILED) {
		perror("mmap");
		goto out;
	}

	/* Populate both mappings and break any zero-page/COW mappings. */
	for (i = 0; i < nr_pages; i++) {
		first[i * page_size] = 1;
		second[i * page_size] = 2;
	}

	ranges[0].start = (uintptr_t)first;
	ranges[0].length = length;
	ranges[1].start = (uintptr_t)second;
	ranges[1].length = length;
	if (prctl(PR_RISCV_PSE_START_RANGES, ranges, 2UL, 0UL, 0UL)) {
		perror("PR_RISCV_PSE_START_RANGES");
		goto out;
	}
	active = true;

	/* Alternate mappings so previous-PTE tracking crosses range boundaries. */
	for (i = 0; i < nr_pages; i++) {
		first[i * page_size]++;
		second[i * page_size]++;
		sum += first[i * page_size] + second[i * page_size];
	}

	if (prctl(PR_RISCV_PSE_GET_STATS, &stats, sizeof(stats), 0UL, 0UL)) {
		perror("PR_RISCV_PSE_GET_STATS");
		goto out;
	}

	printf("ranges=%" PRIu64 " length=%" PRIu64
	       " pages=%" PRIu64 " faults=%" PRIu64
	       " load=%" PRIu64 " store=%" PRIu64
	       " cpu=%" PRIu32 " sum=%" PRIu64 "\n",
	       stats.nr_ranges, stats.total_length, stats.v1.nr_pages,
	       stats.v1.fault_count, stats.v1.load_fault_count,
	       stats.v1.store_fault_count, stats.v1.cpu, sum);

	if (stats.nr_ranges != 2 || stats.total_length != 2 * length ||
	    stats.v1.nr_pages != 2 * nr_pages ||
	    stats.v1.fault_count < 2 * nr_pages) {
		fprintf(stderr, "unexpected multi-range statistics\n");
		goto out;
	}
	status = EXIT_SUCCESS;

out:
	if (active &&
	    prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL)) {
		perror("PR_RISCV_PSE_STOP");
		status = EXIT_FAILURE;
	}
	if (first != MAP_FAILED)
		munmap((void *)first, length);
	if (second != MAP_FAILED)
		munmap((void *)second, length);
	return status;
}
