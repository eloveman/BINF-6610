#!/usr/bin/env bash

set -euo pipefail

# The folder this file is in, whichever folder you run it from, and when this
# run started. Stage 9 finds lib/write_manifest.sh through HERE, and the
# manifest records RUN_STARTED.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# The samplesheet has SIX columns, in this order:
#   sample_id, condition, replicate, library_type, r1_fastq, r2_fastq
# Every stage reads it with `read -r id cond rep lt r1 r2`, and `read` puts
# anything left over into the LAST variable -- so a sheet with extra columns
# would silently put them all in $r2. If you add columns, read them by name.
SHEET=${1:?usage: rnaseq.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: rnaseq.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}

# Configuration. Everything has a default and can be overridden from the
# environment, so no path is written into the code.
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}

QC="${OUT}/qc_raw"; TRIM="${OUT}/trim"; ALN="${OUT}/align"
GVCF="${OUT}/gvcf"; JOINT="${OUT}/joint"; LOG="${OUT}/logs"; RES="${OUT}/results"

#--- two helpers, and they are the only ones ---------------------------------
# Messages go to stderr so that a stage's stdout stays free for data.
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 65; }

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# Catch a typo in the third argument before running anything.
known=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "unknown stage: ${LAST}"

#=============================================================================
# 0 · validate — check everything before computing anything
#=============================================================================
stage_validate() {
    local id cond rep lt r1 r2 problems=0 n1 n2 r1_ok r2_ok

    while IFS=, read -r id cond rep lt r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

        # the files exist and are not empty
        [[ -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }
        if [[ "$lt" == paired ]]; then
            [[ -s "$r2" ]] || { log "$id: declared paired but R2 is missing"; problems=$(( problems + 1 )); }
        fi

        # the r2 column and the declared layout agree
        if [[ -z "$r2" && "$lt" == paired ]]; then
            log "$id: r2_fastq is empty but library_type says paired"
            problems=$(( problems + 1 ))
        fi

        # the gzip streams are whole -- both of them. A stream that fails here is
        # not read below: under pipefail, `gzip -dc` on it would end the script
        # instead of letting it report every problem.
        r1_ok=0 r2_ok=0
        if [[ -s "$r1" ]]; then
            if gzip -t "$r1" 2>/dev/null; then r1_ok=1
            else log "$id: R1 is not a valid gzip file"; problems=$(( problems + 1 )); fi
        fi
        if [[ "$lt" == paired && -s "$r2" ]]; then
            if gzip -t "$r2" 2>/dev/null; then r2_ok=1
            else log "$id: R2 is not a valid gzip file"; problems=$(( problems + 1 )); fi
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
    done < <(tail -n +2 "$SHEET")

    # duplicate sample ids. sort | uniq -d prints only the repeats.
    local dupes
    dupes=$(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)
    [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

    # the reference is where the config says it is
    [[ -s "$REF" ]]       || { log "no reference at ${REF}";  problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]] || { log "no .fai for ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]] || { log "no BWA index for ${REF}"; problems=$(( problems + 1 )); }
    [[ -s "${REF%.fa}.dict" ]] || { log "no .dict for ${REF}"; problems=$(( problems + 1 )); }

    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}

#=============================================================================
# 1 · qc_raw — FastQC on the reads as they arrived
#=============================================================================
stage_qc_raw() {
    local id cond rep lt r1 r2 base
    while IFS=, read -r id cond rep lt r1 r2; do
        # stdout as well as stderr: fastqc prints "application/gzip" per file on
        # STDOUT, which otherwise lands in the terminal and looks like output.
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        [[ "$lt" != paired ]] || fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1

        # fastqc can exit 0 and write nothing. Ask the disk.
        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report"
        log "$id: qc done"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 2 · trim — adapters and low-quality tails
#=============================================================================
stage_trim() {
    local id cond rep lt r1 r2 n
    while IFS=, read -r id cond rep lt r1 r2; do
        if [[ "$lt" == paired ]]; then
            fastp -i "$r1" -I "$r2" \
                  -o "${TRIM}/${id}_R1.fastq.gz" -O "${TRIM}/${id}_R2.fastq.gz" \
                  -j "${LOG}/${id}.fastp.json" -h "${LOG}/${id}.fastp.html" \
                  2> "${LOG}/${id}.fastp.log"
        else
            fastp -i "$r1" -o "${TRIM}/${id}_R1.fastq.gz" \
                  -j "${LOG}/${id}.fastp.json" -h "${LOG}/${id}.fastp.html" \
                  2> "${LOG}/${id}.fastp.log"
        fi

        # trimming can only remove reads. Zero left means something is wrong.
        n=$(gzip -dc "${TRIM}/${id}_R1.fastq.gz" | wc -l)
        (( n > 0 )) || die "$id: nothing survived trimming"
        log "$id: trimmed to $(( n / 4 )) reads"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 3 · align 
#=============================================================================

stage_align() {
    local id cond rep lt r1 r2 rate
    while IFS=, read -r id cond rep lt r1 r2; do
        if [[ "$lt" == paired ]]; then
            bwa mem -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" "${TRIM}/${id}_R2.fastq.gz" \
                2> "${LOG}/${id}.bwa.log"
        else
            bwa mem -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" \
                2> "${LOG}/${id}.bwa.log"
        fi | samtools view -b -o "${ALN}/${id}.raw.bam" -
 
        [[ -s "${ALN}/${id}.raw.bam" ]] || die "$id: bwa wrote an empty BAM"

        rate=$(samtools flagstat "${ALN}/${id}.raw.bam" \
               | awk '/ mapped \(/ && !/primary/ { gsub(/[(%]/, "", $5); print $5; exit }')
        [[ "$rate" =~ ^[0-9.]+$ ]] || die "$id: could not read an alignment rate (got '${rate}')"
        log "$id: ${rate}% aligned"
        awk -v r="$rate" 'BEGIN { exit !(r > 50) }' \
            || die "$id: only ${rate}% — wrong reference, or the mates are mixed up"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 4 · postprocess
#=============================================================================
stage_postprocess() {
    local id cond rep lt r1 r2
    while IFS=, read -r id cond rep lt r1 r2; do
        samtools sort -@ "$THREADS" -o "${ALN}/${id}.sorted.bam" "${ALN}/${id}.raw.bam"
 
        gatk MarkDuplicates \
             -I "${ALN}/${id}.sorted.bam" -O "${ALN}/${id}.bam" \
             -M "${LOG}/${id}.markdup.txt" --VALIDATION_STRINGENCY SILENT \
             > "${LOG}/${id}.markdup.log" 2>&1
 
        samtools index "${ALN}/${id}.bam"
        samtools flagstat "${ALN}/${id}.bam" > "${LOG}/${id}.flagstat.txt"
 
        [[ -s "${ALN}/${id}.bam" && -s "${ALN}/${id}.bam.bai" ]] \
            || die "$id: no indexed BAM after postprocessing"
        log "$id: sorted, duplicates marked, indexed"
    done < <(tail -n +2 "$SHEET")
}
 
#=============================================================================
# 5 · quantify
#=============================================================================
stage_quantify() {
    local id cond rep lt r1 r2
    while IFS=, read -r id cond rep lt r1 r2; do
        gatk HaplotypeCaller \
             -R "$REF" -I "${ALN}/${id}.bam" -L "$REGION" -ERC GVCF \
             --native-pair-hmm-threads "$THREADS" \
             -O "${GVCF}/${id}.g.vcf.gz" \
             > "${LOG}/${id}.haplotypecaller.log" 2>&1
 
        [[ -s "${GVCF}/${id}.g.vcf.gz" ]] || die "$id: HaplotypeCaller wrote no GVCF"
        log "$id: GVCF written"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 6 · merge 
#=============================================================================
stage_merge() {
    local id cond rep lt r1 r2 n_sheet n_vcf
    local -a inputs=()
 
    while IFS=, read -r id cond rep lt r1 r2; do
        [[ -s "${GVCF}/${id}.g.vcf.gz" ]] || die "$id: no GVCF, cannot merge without every sample"
        inputs+=(-V "${GVCF}/${id}.g.vcf.gz")
    done < <(tail -n +2 "$SHEET")
    (( ${#inputs[@]} > 0 )) || die "merge found no samples in ${SHEET}"
 
    gatk CombineGVCFs -R "$REF" "${inputs[@]}" -L "$REGION" \
         -O "${JOINT}/cohort.g.vcf.gz" > "${LOG}/combinegvcfs.log" 2>&1
 
    gatk GenotypeGVCFs -R "$REF" -V "${JOINT}/cohort.g.vcf.gz" -L "$REGION" \
         -O "${JOINT}/cohort.vcf.gz" > "${LOG}/genotypegvcfs.log" 2>&1
 
    [[ -s "${JOINT}/cohort.vcf.gz" ]] || die "GenotypeGVCFs wrote no VCF"
 
    n_sheet=$(awk -F, 'NR>1' "$SHEET" | wc -l)
    n_vcf=$(bcftools query -l "${JOINT}/cohort.vcf.gz" | wc -l)
    (( n_vcf == n_sheet )) || die "VCF has ${n_vcf} sample columns for ${n_sheet} samples"
    log "joint VCF: ${n_vcf} samples"
}

#=============================================================================
# 7 · analyze 
#=============================================================================
stage_analyze() {
    local n
    gatk VariantFiltration -R "$REF" -V "${JOINT}/cohort.vcf.gz" \
         --filter-expression "QD < 2.0"  --filter-name "QD2" \
         --filter-expression "FS > 60.0" --filter-name "FS60" \
         --filter-expression "MQ < 40.0" --filter-name "MQ40" \
         --filter-expression "SOR > 3.0" --filter-name "SOR3" \
         -O "${RES}/cohort.filtered.vcf.gz" > "${LOG}/variantfiltration.log" 2>&1
 
    [[ -s "${RES}/cohort.filtered.vcf.gz" ]] || die "VariantFiltration wrote no VCF"
    n=$(bcftools view -H "${RES}/cohort.filtered.vcf.gz" | wc -l)
    (( n > 0 )) || die "the filtered VCF has no variant records"
    log "filtered VCF: ${n} records"
}

#=============================================================================
# 8 · qc_report — MultiQC over every log this run produced
#=============================================================================
stage_qc_report() {
    multiqc -q -f -o "$RES" "$QC" "$LOG" > "${LOG}/multiqc.log" 2>&1
    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "QC report written"
}

#=============================================================================
# 9 · publish — say what produced this, in a file anyone can read
#=============================================================================
stage_publish() {
    # The course's script writes results/manifest.json: the commit this code was
    # on, the samples, the reference and annotation, the machine, every published
    # file with its checksum, and each tool's version. 
    PIPELINE_NAME=variant-call \
    bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"

    log "results in ${RES}:"
    ls -1 "$RES" >&2
}

#=============================================================================
# the driver — ten stages, in order, one after another
#=============================================================================
# Run the stages in order and stop after the one named on the command line.
# `"stage_${stage}"` calls the function whose name is built from the stage name.
mkdir -p "$QC" "$TRIM" "$ALN" "$GVCF" "$JOINT" "$LOG" "$RES"
n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"
