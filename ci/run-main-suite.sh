#!/usr/bin/env bash
set -euo pipefail

readonly GROUP_COUNT=5

all_tests=()
while IFS= read -r test_name; do
    all_tests+=("$test_name")
done < <(./runtest --list-tests)

if [[ ${#all_tests[@]} -ne 78 ]]; then
    echo "Expected 78 upstream test units, found ${#all_tests[@]}" >&2
    exit 1
fi

# Keep the upstream order while isolating the historically slow multi-master
# PSYNC unit. The bounds are zero-based and inclusive.
group_bounds() {
    case "$1" in
        core-early)        printf '%s %s\n' 0 28 ;;
        replication)       printf '%s %s\n' 29 38 ;;
        persistence-tools) printf '%s %s\n' 39 48 ;;
        psync-multimaster) printf '%s %s\n' 49 49 ;;
        core-late)         printf '%s %s\n' 50 77 ;;
        *)
            echo "Unknown main-suite group: $1" >&2
            exit 2
            ;;
    esac
}

verify_partition() {
    local groups=(core-early replication persistence-tools psync-multimaster core-late)
    local rebuilt=()
    local group first last index

    [[ ${#groups[@]} -eq $GROUP_COUNT ]]
    for group in "${groups[@]}"; do
        read -r first last < <(group_bounds "$group")
        for ((index = first; index <= last; index++)); do
            rebuilt+=("${all_tests[index]}")
        done
    done

    [[ ${#rebuilt[@]} -eq ${#all_tests[@]} ]]
    for ((index = 0; index < ${#all_tests[@]}; index++)); do
        if [[ "${rebuilt[index]}" != "${all_tests[index]}" ]]; then
            echo "Partition mismatch at unit $((index + 1))" >&2
            exit 1
        fi
    done

    [[ "${all_tests[29]}" == integration/block-repl ]]
    [[ "${all_tests[49]}" == integration/replication-psync-multimaster ]]
    [[ "${all_tests[50]}" == unit/pubsub ]]
    echo "Verified: all ${#all_tests[@]} upstream units occur exactly once in $GROUP_COUNT groups."
}

if [[ "${1:-}" == --verify ]]; then
    verify_partition
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 --verify|<group>" >&2
    exit 2
fi

verify_partition
read -r first last < <(group_bounds "$1")

test_args=()
for ((index = first; index <= last; index++)); do
    test_args+=(--single "${all_tests[index]}")
done

# This allocator-layout-sensitive test explicitly expects a fresh process.
# Keep it in the full partition, but run the individual case in its own CI job.
if [[ "$1" == core-late ]]; then
    test_args+=(--skiptest "Active defrag edge case")
fi

echo "Running $1: $((last - first + 1)) units (${all_tests[first]} through ${all_tests[last]})"
exec ./runtest \
    --clients 1 \
    --verbose \
    --dump-logs \
    --tls \
    --config server-threads 3 \
    "${test_args[@]}"
