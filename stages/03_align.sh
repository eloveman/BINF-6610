#!/usr/bin/env bash
# 3 · align — BWA-MEM to the whole reference, read group SM = sample_id
set -euo pipefail

stage_align() {
    local id cond rep lt r1 r2 rate
    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        if [[ "$lt" == paired ]]; then
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" "${TRIM}/${id}_R2.fastq.gz" \
                2> "${LOG}/${id}.bwa.log"
        else
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" \
                2> "${LOG}/${id}.bwa.log"
        fi | samtools view -@ "$THREADS" -b -o "${ALN}/${id}.raw.bam" -

        [[ -s "${ALN}/${id}.raw.bam" ]] || die "$id: bwa wrote an empty BAM"

        rate=$(samtools flagstat "${ALN}/${id}.raw.bam" \
               | awk '/ mapped \(/ && !/primary/ { gsub(/[(%]/, "", $5); print $5; exit }')
        [[ "$rate" =~ ^[0-9.]+$ ]] || die "$id: could not read an alignment rate (got '${rate}')"
        log "$id: ${rate}% aligned"
        awk -v r="$rate" 'BEGIN { exit !(r > 50) }' \
            || die "$id: only ${rate}% aligned -- wrong reference, or the mates are mixed up"
    done < <(rows)
}
