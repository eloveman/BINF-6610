#!/usr/bin/env bash
# Shared by run_pipeline.sh and run_sample.sh: the settings, log and die, the
# output folders, and reading the samplesheet by column name.
# Sourced, never run on its own. The entry point sets SHEET, OUT and SAMPLE first.
set -euo pipefail

# Only the reference and the calling region change between laptop and Explorer.
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}
TMP_BASE=${TMPDIR:-/tmp}      # on Explorer the job script sets TMPDIR=/tmp/<jobid>

QC="${OUT}/qc_raw"; TRIM="${OUT}/trim"; ALN="${OUT}/align"
GVCF="${OUT}/gvcf"; JOINT="${OUT}/joint"; LOG="${OUT}/logs"; RES="${OUT}/results"

# Messages go to stderr so that stdout stays free for data.
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 65; }

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

#--- the samplesheet, read by column name -------------------------------------
# The week-1 sheet has 6 columns, the Explorer sheet has 10, in a different
# order is fine too: columns are found by their header names.
# rows() prints one line per sample, fields joined by the unit separator (\x1f),
# in this order:  sample_id condition replicate library_type r1_fastq r2_fastq
# \x1f is not whitespace, so an empty field (r2 of a single-end sample) stays
# empty instead of collapsing, and it never occurs in a name like "Donor 3-rep1".
# If SAMPLE is set, only that sample's row is printed.
FS1=$'\x1f'
NEEDED_COLUMNS=(sample_id condition replicate library_type r1_fastq r2_fastq)

check_columns() {
    [[ -s "$SHEET" ]] || die "no samplesheet at ${SHEET}"
    local missing
    missing=$(awk -F',' -v need="${NEEDED_COLUMNS[*]}" '
        NR == 1 {
            sub(/\r$/, "")
            for (i = 1; i <= NF; i++) have[$i] = 1
            n = split(need, want, " ")
            for (j = 1; j <= n; j++) if (!(want[j] in have)) printf "%s ", want[j]
            exit
        }' "$SHEET")
    [[ -z "$missing" ]] || die "samplesheet ${SHEET} has no column(s): ${missing}"
}

rows() {
    awk -F',' -v want="${SAMPLE:-}" -v OFS="$FS1" '
        { sub(/\r$/, "") }
        NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        $0 == "" { next }
        want == "" || $col["sample_id"] == want {
            print $col["sample_id"], $col["condition"], $col["replicate"],
                  $col["library_type"], $col["r1_fastq"], $col["r2_fastq"]
        }' "$SHEET"
}

make_dirs() {
    mkdir -p "$QC" "$TRIM" "$ALN" "$GVCF" "$JOINT" "$LOG" "$RES"
}

#--- running stages -----------------------------------------------------------
stage_index() {
    local i
    for i in "${!STAGES[@]}"; do
        if [[ "${STAGES[$i]}" == "$1" ]]; then echo "$i"; return 0; fi
    done
    return 1
}

# run_stages FIRST LAST: run every stage from FIRST to LAST, in order.
# Both names are checked before anything runs, so a typo costs nothing.
run_stages() {
    local first=$1 last=$2 a b i
    a=$(stage_index "$first") || die "unknown stage: ${first}"
    b=$(stage_index "$last")  || die "unknown stage: ${last}"
    (( a <= b )) || die "stage ${first} comes after stage ${last}"
    for (( i = a; i <= b; i++ )); do
        log "===== stage ${i} : ${STAGES[$i]} ====="
        "stage_${STAGES[$i]}"
    done
    log "done"
}
