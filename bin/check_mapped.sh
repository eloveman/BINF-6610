#!/usr/bin/env bash
# check_mapped.sh BAM MIN_PERCENT: fail if the mapping rate is below MIN_PERCENT
set -euo pipefail
bam=$1
min=$2

rate=$(samtools flagstat "$bam" \
       | awk '/ mapped \(/ && !/primary/ { gsub(/[(%]/, "", $5); print $5; exit }')
echo "$bam: ${rate}% mapped (minimum ${min}%)" >&2

if ! awk -v r="$rate" -v min="$min" 'BEGIN { exit !(r + 0 >= min + 0) }'; then
    echo "$bam: mapping rate below ${min}%" >&2
    exit 1
fi
