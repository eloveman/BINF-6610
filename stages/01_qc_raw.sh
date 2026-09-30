#!/usr/bin/env bash
# 1 · qc_raw — FastQC on the reads as they arrived
set -euo pipefail

stage_qc_raw() {
    local id cond rep lt r1 r2 base
    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        # fastqc prints to stdout as well, so both go to the log
        fastqc -q -t "$THREADS" -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        [[ "$lt" != paired ]] || fastqc -q -t "$THREADS" -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1

        # fastqc can exit 0 and write nothing. Ask the disk.
        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report"
        log "$id: qc done"
    done < <(rows)
}
