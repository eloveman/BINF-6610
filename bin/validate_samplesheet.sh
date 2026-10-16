#!/usr/bin/env bash
# 0 · validate — check everything before computing anything, and report every
# problem together rather than stopping at the first.
# Usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa>
# Runs inside a Nextflow task: every FASTQ and reference file is linked into
# the task folder, so each is opened by its file name, not the sheet's path.
set -euo pipefail

sheet="$1"
REF="$2"
SHEET_DIR="$(cd "$(dirname "$1")" && pwd)"
problems=0

log() { echo "[validate] $*" >&2; }

# data rows, as sample_id,library_type,r1_fastq,r2_fastq — found by column
# name in the header, so extra columns, in any order, do not matter
rows() {
    tr -d '\r' < "$sheet" | awk -F, '
        NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        NF > 0  { print $col["sample_id"] "," $col["library_type"] "," $col["r1_fastq"] "," $col["r2_fastq"] }'
}

while IFS=, read -r id lt r1 r2; do
    [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

    # the samplesheet's paths do not exist in here; the files' names do
    if [[ -n "$r1" ]]; then [[ "$r1" == /* ]] || r1="${SHEET_DIR}/$r1"; fi
    if [[ -n "$r2" ]]; then [[ "$r2" == /* ]] || r2="${SHEET_DIR}/$r2"; fi

    # the layout is one the pipeline knows
    if [[ "$lt" != paired && "$lt" != single ]]; then
        log "$id: library_type is '${lt}', expected paired or single"
        problems=$(( problems + 1 ))
    fi

    # the files exist and are not empty
    [[ -n "$r1" && -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }
    if [[ "$lt" == paired ]]; then
        if [[ -z "$r2" ]]; then
            log "$id: r2_fastq is empty but library_type says paired"
            problems=$(( problems + 1 ))
        elif [[ ! -s "$r2" ]]; then
            log "$id: R2 missing or empty: $r2"
            problems=$(( problems + 1 ))
        fi
    fi

    # the gzip streams are whole
    r1_ok=0 r2_ok=0
    if [[ -n "$r1" && -s "$r1" ]]; then
        if gzip -t "$r1" 2>/dev/null; then r1_ok=1
        else log "$id: R1 is not a valid gzip file (truncated?): $r1"; problems=$(( problems + 1 )); fi
    fi
    if [[ "$lt" == paired && -n "$r2" && -s "$r2" ]]; then
        if gzip -t "$r2" 2>/dev/null; then r2_ok=1
        else log "$id: R2 is not a valid gzip file (truncated?): $r2"; problems=$(( problems + 1 )); fi
    fi

    # the records are whole, and the mates agree
    if (( r1_ok )); then
        n1=$(gzip -dc "$r1" | wc -l)
        (( n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"
                               problems=$(( problems + 1 )); }
        if (( r2_ok )); then
            n2=$(gzip -dc "$r2" | wc -l)
            (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"
                                problems=$(( problems + 1 )); }
        fi
    fi
    log "$id: checked"
done < <(rows)

# duplicate sample ids
dupes=$(rows | awk -F, '{ print $1 }' | sort | uniq -d | tr '\n' ' ')
[[ -z "${dupes// /}" ]] || { log "duplicate sample_id: ${dupes}"; problems=$(( problems + 1 )); }

# the reference and its index files were handed to this task
[[ -s "$REF" ]]            || { log "no reference: ${REF}";    problems=$(( problems + 1 )); }
[[ -s "${REF}.fai" ]]      || { log "no .fai for ${REF}";      problems=$(( problems + 1 )); }
[[ -s "${REF}.bwt" ]]      || { log "no BWA index for ${REF}"; problems=$(( problems + 1 )); }
[[ -s "${REF%.fa}.dict" ]] || { log "no .dict for ${REF}";     problems=$(( problems + 1 )); }

if (( problems > 0 )); then
    log "validation failed with ${problems} problem(s)"
    exit 1
fi
log "validation passed"
