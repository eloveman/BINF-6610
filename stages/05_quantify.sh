#!/usr/bin/env bash
# 5 · quantify — HaplotypeCaller per sample, into a GVCF
set -euo pipefail

stage_quantify() {
    local id cond rep lt r1 r2 part final
    while IFS="$FS1" read -r id cond rep lt r1 r2; do
        # Write under a temporary name and rename only when it is complete, so a
        # job cancelled mid-write never leaves a file that looks finished.
        part="${GVCF}/${id}.partial.g.vcf.gz"
        final="${GVCF}/${id}.g.vcf.gz"
        rm -f "$part" "${part}.tbi"

        gatk HaplotypeCaller \
             -R "$REF" -I "${ALN}/${id}.bam" -L "$REGION" -ERC GVCF \
             --native-pair-hmm-threads "$THREADS" \
             --tmp-dir "${TMP_BASE}" \
             -O "$part" \
             > "${LOG}/${id}.haplotypecaller.log" 2>&1

        [[ -s "$part" && -s "${part}.tbi" ]] || die "$id: HaplotypeCaller wrote no GVCF"
        mv -f "${part}.tbi" "${final}.tbi"
        mv -f "$part" "$final"
        log "$id: GVCF written"
    done < <(rows)
}
