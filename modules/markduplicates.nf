process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.bam"), path("${meta.id}.bam.bai")

    script:
    """
    samtools sort -@ ${task.cpus} -T ${meta.id}.sort \\
        -o ${meta.id}.sorted.bam ${bam}

    gatk MarkDuplicates \\
         -I ${meta.id}.sorted.bam -O ${meta.id}.bam \\
         -M ${meta.id}.markdup.txt --VALIDATION_STRINGENCY SILENT \\
         --TMP_DIR .

    samtools index -@ ${task.cpus} ${meta.id}.bam
    """
}
