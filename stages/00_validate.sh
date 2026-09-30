#!/usr/bin/env bash
# 0 · validate — check everything before computing anything, and report every
# problem together rather than stopping at the first.
set -euo pipefail

stage_validate() {
    local id cond rep lt r1 r2 problems=0 n1 n2 r1_ok r2_ok dupes

    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

        # the layout is one the pipeline knows
        if [[ "$lt" != paired && "$lt" != single ]]; then
            log "$id: library_type is '${lt}', expected paired or single"
            problems=$(( problems + 1 ))
        fi

        # the files exist and are not empty
        [[ -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }
        if [[ "$lt" == paired ]]; then
            if [[ -z "$r2" ]]; then
                log "$id: r2_fastq is empty but library_type says paired"
                problems=$(( problems + 1 ))
            elif [[ ! -s "$r2" ]]; then
                log "$id: R2 missing or empty: $r2"
                problems=$(( problems + 1 ))
            fi
        fi

        # the gzip streams are whole. A stream that fails here is not read
        # below: under pipefail, gzip -dc on it would end the script instead
        # of letting it report every problem.
        r1_ok=0 r2_ok=0
        if [[ -s "$r1" ]]; then
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

    # duplicate sample ids, across the whole sheet even when running one sample
    dupes=$(SAMPLE="" rows | awk -F"$FS1" '{ print $1 }' | sort | uniq -d | tr '\n' ' ')
    [[ -z "${dupes// /}" ]] || { log "duplicate sample_id: ${dupes}"; problems=$(( problems + 1 )); }

    # the reference is where the config says it is
    [[ -s "$REF" ]]            || { log "no reference at ${REF}";  problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]]      || { log "no .fai for ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]]      || { log "no BWA index for ${REF}"; problems=$(( problems + 1 )); }
    [[ -s "${REF%.fa}.dict" ]] || { log "no .dict for ${REF}";     problems=$(( problems + 1 )); }

    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}
