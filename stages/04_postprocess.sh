#!/usr/bin/env bash
# 4 · postprocess — sort, mark duplicates, index
set -euo pipefail

stage_postprocess() {
    local id cond rep lt r1 r2
    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        # -T: spill files go on the node's own disk, not shared storage
        samtools sort -@ "$THREADS" -T "${TMP_BASE}/${id}.sort" \
            -o "${ALN}/${id}.sorted.bam" "${ALN}/${id}.raw.bam"

        gatk MarkDuplicates \
             -I "${ALN}/${id}.sorted.bam" -O "${ALN}/${id}.bam" \
             -M "${LOG}/${id}.markdup.txt" --VALIDATION_STRINGENCY SILENT \
             --TMP_DIR "${TMP_BASE}" \
             > "${LOG}/${id}.markdup.log" 2>&1

        samtools index -@ "$THREADS" "${ALN}/${id}.bam"
        samtools flagstat "${ALN}/${id}.bam" > "${LOG}/${id}.flagstat.txt"

        [[ -s "${ALN}/${id}.bam" && -s "${ALN}/${id}.bam.bai" ]] \
            || die "$id: no indexed BAM after postprocessing"
        log "$id: sorted, duplicates marked, indexed"
    done < <(rows)
}
