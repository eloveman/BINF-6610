process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    """
    gatk HaplotypeCaller \\
         -R ${ref} -I ${bam} -L ${params.region} -ERC GVCF \\
         --native-pair-hmm-threads ${task.cpus} \\
         --tmp-dir . \\
         -O ${meta.id}.g.vcf.gz
    """
}
