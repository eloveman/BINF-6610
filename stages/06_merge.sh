#!/usr/bin/env bash
# 6 · merge — combine every sample's GVCF, then joint-genotype
set -euo pipefail

stage_merge() {
    local id cond rep lt r1 r2 n_sheet n_vcf
    local -a inputs=()

    # every sample in the sheet must have its GVCF, or the cohort is short
    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        [[ -s "${GVCF}/${id}.g.vcf.gz" ]] || die "$id: no GVCF, cannot merge without every sample"
        inputs+=(-V "${GVCF}/${id}.g.vcf.gz")
    done < <(rows)
    (( ${#inputs[@]} > 0 )) || die "merge found no samples in ${SHEET}"

    gatk CombineGVCFs -R "$REF" "${inputs[@]}" -L "$REGION" \
         --tmp-dir "${TMP_BASE}" \
         -O "${JOINT}/cohort.g.vcf.gz" > "${LOG}/combinegvcfs.log" 2>&1

    gatk GenotypeGVCFs -R "$REF" -V "${JOINT}/cohort.g.vcf.gz" -L "$REGION" \
         --tmp-dir "${TMP_BASE}" \
         -O "${JOINT}/cohort.vcf.gz" > "${LOG}/genotypegvcfs.log" 2>&1

    [[ -s "${JOINT}/cohort.vcf.gz" ]] || die "GenotypeGVCFs wrote no VCF"

    n_sheet=$(rows | wc -l | tr -d ' ')
    n_vcf=$(bcftools query -l "${JOINT}/cohort.vcf.gz" | wc -l | tr -d ' ')
    (( n_vcf == n_sheet )) || die "VCF has ${n_vcf} sample columns for ${n_sheet} samples"
    log "joint VCF: ${n_vcf} samples"
}
