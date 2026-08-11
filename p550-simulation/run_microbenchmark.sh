#!/usr/bin/env bash
set -euo pipefail

trials=${TRIALS:-30}
accesses=${ACCESSES:-1000000}
cpu=${CPU:-0}
pattern=${PATTERN:-sequential}
seed=${SEED:-1}
operation=${OPERATION:-write}
output=${OUTPUT:-microbenchmark-results.csv}
pages=(64 128 256 512 1024 2048 4096)

if (( EUID != 0 )); then
	echo "run this script with sudo" >&2
	exit 1
fi

printf '%s\n' \
	'trial,pages,memory_bytes,mode,operation,pattern,seed,accesses,total_ns,average_ns,total_cycles,average_cycles,cpu,faults,load_faults,store_faults,checksum' \
	> "$output"

for page_count in "${pages[@]}"; do
	for ((trial = 1; trial <= trials; trial++)); do
		if (( trial % 2 )); then
			modes=(normal custom)
		else
			modes=(custom normal)
		fi

		for mode in "${modes[@]}"; do
			line=$(taskset -c "$cpu" ./pse_microbench \
				"$mode" "$page_count" "$accesses" "$pattern" \
				"$seed" "$operation")
			declare -A value=()
			for field in $line; do
				value["${field%%=*}"]=${field#*=}
			done
			printf '%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
				"$trial" "$page_count" "${value[memory_bytes]}" \
				"$mode" "${value[operation]}" "${value[pattern]}" \
				"${value[seed]}" "${value[accesses]}" \
				"${value[total_ns]}" \
				"${value[average_ns]}" "${value[total_cycles]}" \
				"${value[average_cycles]}" "${value[cpu]}" \
				"${value[faults]}" "${value[load_faults]}" \
				"${value[store_faults]}" "${value[checksum]}" \
				>> "$output"
		done
	done
done

echo "wrote $output"
