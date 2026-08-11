// SPDX-License-Identifier: GPL-2.0-only
#define _GNU_SOURCE

#include <errno.h>
#include <inttypes.h>
#include <linux/perf_event.h>
#include <sched.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <time.h>
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

enum benchmark_mode {
	MODE_NORMAL,
	MODE_CUSTOM,
};

enum access_pattern {
	PATTERN_SEQUENTIAL,
	PATTERN_SEQUENTIAL_64,
	PATTERN_RANDOM,
};

enum memory_operation {
	OPERATION_WRITE,
	OPERATION_READ,
};

#define ACCESS_GRANULE	64UL

struct cycle_counter {
	int fd;
	void *metadata;
};

static void usage(const char *program)
{
	fprintf(stderr,
		"Usage: %s <normal|custom> [pages] [accesses]"
		" [sequential|sequential64|random] [seed] [write|read]\n",
		program);
}

static uint64_t next_random(uint64_t *state)
{
	uint64_t value = *state;

	value ^= value >> 12;
	value ^= value << 25;
	value ^= value >> 27;
	*state = value;
	return value * 0x2545f4914f6cdd1dULL;
}

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

static uint64_t elapsed_ns(const struct timespec *start,
			   const struct timespec *end)
{
	return (uint64_t)(end->tv_sec - start->tv_sec) * 1000000000ULL +
	       (uint64_t)(end->tv_nsec - start->tv_nsec);
}

static uint64_t read_cycles(void)
{
#ifdef __riscv
	uint64_t cycles;

	__asm__ __volatile__("rdcycle %0" : "=r" (cycles) : : "memory");
	return cycles;
#else
	/*
	 * Keep host-side warning checks available. Benchmark results are valid
	 * only for the RISC-V binary.
	 */
	return 0;
#endif
}

static int start_cycle_counter(struct cycle_counter *counter,
			       size_t page_size)
{
#ifdef __riscv
	struct perf_event_attr attr = {
		.type = PERF_TYPE_HARDWARE,
		.size = sizeof(attr),
		.config = PERF_COUNT_HW_CPU_CYCLES,
		.disabled = 1,
		.exclude_hv = 1,
	};

	counter->fd = syscall(SYS_perf_event_open, &attr, 0, -1, -1, 0);
	if (counter->fd < 0)
		return -1;

	/*
	 * Mapping the perf metadata page enables direct user access to the
	 * counter on RISC-V. Keep it mapped until all rdcycle reads finish.
	 */
	counter->metadata = mmap(NULL, page_size, PROT_READ, MAP_SHARED,
				 counter->fd, 0);
	if (counter->metadata == MAP_FAILED)
		goto close_fd;

	if (ioctl(counter->fd, PERF_EVENT_IOC_RESET, 0) ||
	    ioctl(counter->fd, PERF_EVENT_IOC_ENABLE, 0))
		goto unmap_metadata;

	return 0;

unmap_metadata:
	munmap(counter->metadata, page_size);
close_fd:
	close(counter->fd);
	return -1;
#else
	(void)counter;
	(void)page_size;
	errno = EOPNOTSUPP;
	return -1;
#endif
}

static void stop_cycle_counter(struct cycle_counter *counter,
			       size_t page_size)
{
	ioctl(counter->fd, PERF_EVENT_IOC_DISABLE, 0);
	munmap(counter->metadata, page_size);
	close(counter->fd);
}

int main(int argc, char **argv)
{
	struct pr_riscv_pse_stats stats = {};
	struct cycle_counter counter = {
		.fd = -1,
		.metadata = MAP_FAILED,
	};
	const size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
	enum benchmark_mode mode;
	enum access_pattern pattern = PATTERN_SEQUENTIAL;
	enum memory_operation operation = OPERATION_WRITE;
	size_t nr_pages = 4096;
	size_t nr_accesses;
	uint32_t *random_lines = NULL;
	volatile unsigned char *mapping;
	struct timespec begin;
	struct timespec end;
	uint64_t total_ns;
	uint64_t begin_cycles;
	uint64_t end_cycles;
	uint64_t total_cycles;
	uint64_t checksum = 0;
	uint64_t seed = 1;
	uint64_t random_state;
	size_t length;
	size_t nr_cache_lines;
	size_t i;
	size_t page_index;
	int cpu;

	if (argc < 2 || argc > 7) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}
	if (!strcmp(argv[1], "normal"))
		mode = MODE_NORMAL;
	else if (!strcmp(argv[1], "custom"))
		mode = MODE_CUSTOM;
	else {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	if (argc >= 3)
		nr_pages = strtoul(argv[2], NULL, 0);
	nr_accesses = nr_pages;
	if (argc >= 4)
		nr_accesses = strtoul(argv[3], NULL, 0);
	if (argc >= 5) {
		if (!strcmp(argv[4], "sequential"))
			pattern = PATTERN_SEQUENTIAL;
		else if (!strcmp(argv[4], "sequential64"))
			pattern = PATTERN_SEQUENTIAL_64;
		else if (!strcmp(argv[4], "random"))
			pattern = PATTERN_RANDOM;
		else {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}
	if (argc >= 6)
		seed = strtoull(argv[5], NULL, 0);
	if (argc == 7) {
		if (!strcmp(argv[6], "write"))
			operation = OPERATION_WRITE;
		else if (!strcmp(argv[6], "read"))
			operation = OPERATION_READ;
		else {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}
	if (!nr_pages || page_size == (size_t)-1 ||
	    nr_pages > SIZE_MAX / page_size || !nr_accesses) {
		fprintf(stderr, "invalid page or access count\n");
		return EXIT_FAILURE;
	}
	length = nr_pages * page_size;
	nr_cache_lines = length / ACCESS_GRANULE;
	if (pattern == PATTERN_RANDOM &&
	    (nr_cache_lines > UINT32_MAX ||
	     nr_accesses > SIZE_MAX / sizeof(*random_lines))) {
		fprintf(stderr, "random access array is too large\n");
		return EXIT_FAILURE;
	}

	if (pin_to_current_cpu()) {
		perror("sched_setaffinity");
		return EXIT_FAILURE;
	}
	cpu = sched_getcpu();

	mapping = mmap(NULL, length, PROT_READ | PROT_WRITE,
		       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (mapping == MAP_FAILED) {
		perror("mmap");
		return EXIT_FAILURE;
	}

	/*
	 * Populate every 4 KiB PTE and resolve COW before either measurement.
	 * This keeps normal mode from measuring demand allocation faults.
	 */
	for (i = 0; i < nr_pages; i++)
		mapping[i * page_size] = 0;

	if (pattern == PATTERN_RANDOM) {
		random_lines = malloc(nr_accesses * sizeof(*random_lines));
		if (!random_lines) {
			perror("malloc random access array");
			goto fail;
		}

		random_state = seed ? seed : 1;
		for (i = 0; i < nr_accesses; i++)
			random_lines[i] =
				next_random(&random_state) % nr_cache_lines;
	}

	if (mode == MODE_NORMAL) {
		/*
		 * Changing permissions in both directions invalidates cached
		 * translations while leaving the populated PTEs present.
		 */
		if (mprotect((void *)mapping, length, PROT_NONE) ||
		    mprotect((void *)mapping, length, PROT_READ | PROT_WRITE)) {
			perror("mprotect");
			goto fail;
		}
	} else if (prctl(PR_RISCV_PSE_START, (unsigned long)mapping, length,
			 0UL, 0UL)) {
		perror("PR_RISCV_PSE_START");
		goto fail;
	}

	if (start_cycle_counter(&counter, page_size)) {
		perror("perf cycle counter");
		fprintf(stderr, "run as root when kernel cycles are restricted\n");
		goto stop;
	}

	__asm__ __volatile__("" ::: "memory");
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &begin)) {
		perror("clock_gettime");
		goto stop_counter;
	}
	begin_cycles = read_cycles();

	if (pattern == PATTERN_RANDOM) {
		if (operation == OPERATION_WRITE) {
			for (i = 0; i < nr_accesses; i++)
				mapping[(size_t)random_lines[i] *
					ACCESS_GRANULE] = 1;
		} else {
			for (i = 0; i < nr_accesses; i++)
				checksum += mapping[(size_t)random_lines[i] *
						    ACCESS_GRANULE];
		}
	} else if (pattern == PATTERN_SEQUENTIAL_64) {
		size_t line_index = 0;

		if (operation == OPERATION_WRITE) {
			for (i = 0; i < nr_accesses; i++) {
				mapping[line_index * ACCESS_GRANULE] = 1;
				if (++line_index == nr_cache_lines)
					line_index = 0;
			}
		} else {
			for (i = 0; i < nr_accesses; i++) {
				checksum +=
					mapping[line_index * ACCESS_GRANULE];
				if (++line_index == nr_cache_lines)
					line_index = 0;
			}
		}
	} else {
		page_index = 0;
		if (operation == OPERATION_WRITE) {
			for (i = 0; i < nr_accesses; i++) {
				mapping[page_index * page_size] = 1;
				if (++page_index == nr_pages)
					page_index = 0;
			}
		} else {
			for (i = 0; i < nr_accesses; i++) {
				checksum += mapping[page_index * page_size];
				if (++page_index == nr_pages)
					page_index = 0;
			}
		}
	}

	__asm__ __volatile__("" ::: "memory");
	end_cycles = read_cycles();
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &end)) {
		perror("clock_gettime");
		goto stop_counter;
	}

	total_ns = elapsed_ns(&begin, &end);
	total_cycles = end_cycles - begin_cycles;
	stop_cycle_counter(&counter, page_size);

	if (mode == MODE_CUSTOM &&
	    prctl(PR_RISCV_PSE_GET_STATS, &stats, sizeof(stats), 0UL, 0UL)) {
		perror("PR_RISCV_PSE_GET_STATS");
		goto stop;
	}

	if (mode == MODE_CUSTOM &&
	    prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL)) {
		perror("PR_RISCV_PSE_STOP");
		goto fail;
	}

	printf("mode=%s operation=%s pattern=%s pages=%zu memory_bytes=%zu"
	       " accesses=%zu seed=%" PRIu64 " total_ns=%" PRIu64
	       " average_ns=%.3f total_cycles=%" PRIu64
	       " average_cycles=%.3f cpu=%d faults=%" PRIu64
	       " load_faults=%" PRIu64 " store_faults=%" PRIu64
	       " checksum=%" PRIu64 "\n",
	       mode == MODE_NORMAL ? "normal" : "custom",
	       operation == OPERATION_WRITE ? "write" : "read",
	       pattern == PATTERN_SEQUENTIAL ? "sequential" :
	       pattern == PATTERN_SEQUENTIAL_64 ? "sequential64" : "random",
	       nr_pages, length, nr_accesses, seed, total_ns,
	       (double)total_ns / nr_accesses, total_cycles,
	       (double)total_cycles / nr_accesses, cpu,
	       stats.fault_count, stats.load_fault_count,
	       stats.store_fault_count, checksum);

	if (munmap((void *)mapping, length)) {
		perror("munmap");
		free(random_lines);
		return EXIT_FAILURE;
	}
	free(random_lines);
	return EXIT_SUCCESS;

stop_counter:
	stop_cycle_counter(&counter, page_size);
stop:
	if (mode == MODE_CUSTOM)
		prctl(PR_RISCV_PSE_STOP, 0UL, 0UL, 0UL, 0UL);
fail:
	munmap((void *)mapping, length);
	free(random_lines);
	return EXIT_FAILURE;
}
