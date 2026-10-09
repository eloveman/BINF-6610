process FILTER {
    container params.containers.gatk

    input:
    tuple path(vcf), path(tbi)
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'variants.tsv',           emit: table

    script:
    """
    gatk VariantFiltration -R ${ref} -V ${vcf} \\
         --filter-expression "QD < 2.0"  --filter-name "QD2" \\
         --filter-expression "FS > 60.0" --filter-name "FS60" \\
         --filter-expression "MQ < 40.0" --filter-name "MQ40" \\
         --filter-expression "SOR > 3.0" --filter-name "SOR3" \\
         --tmp-dir . \\
         -O cohort.filtered.vcf.gz

    printf 'chrom\\tpos\\tref\\talt\\tqual\\tfilter\\n' > variants.tsv
    bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%QUAL\\t%FILTER\\n' \\
        cohort.filtered.vcf.gz >> variants.tsv
    """
}
