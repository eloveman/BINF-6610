process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict

    output:
    tuple path('cohort.vcf.gz'), path('cohort.vcf.gz.tbi')

    script:
    def inputs = (gvcfs instanceof List ? gvcfs : [gvcfs]).collect { "-V ${it}" }.join(' ')
    """
    gatk CombineGVCFs -R ${ref} ${inputs} -L ${params.region} \\
         --tmp-dir . \\
         -O cohort.g.vcf.gz

    gatk GenotypeGVCFs -R ${ref} -V cohort.g.vcf.gz -L ${params.region} \\
         --tmp-dir . \\
         -O cohort.vcf.gz
    """
}
