#!/usr/bin/env bash
# 7 · analyze — GATK hard filters; failing sites are labelled, not removed
set -euo pipefail

stage_analyze() {
    local n
    gatk VariantFiltration -R "$REF" -V "${JOINT}/cohort.vcf.gz" \
         --filter-expression "QD < 2.0"  --filter-name "QD2" \
         --filter-expression "FS > 60.0" --filter-name "FS60" \
         --filter-expression "MQ < 40.0" --filter-name "MQ40" \
         --filter-expression "SOR > 3.0" --filter-name "SOR3" \
         --tmp-dir "${TMP_BASE}" \
         -O "${RES}/cohort.filtered.vcf.gz" > "${LOG}/variantfiltration.log" 2>&1

    [[ -s "${RES}/cohort.filtered.vcf.gz" ]] || die "VariantFiltration wrote no VCF"
    n=$(bcftools view -H "${RES}/cohort.filtered.vcf.gz" | wc -l | tr -d ' ')
    (( n > 0 )) || die "the filtered VCF has no variant records"
    log "filtered VCF: ${n} records"
}
