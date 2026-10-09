process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.raw.bam")

    script:
    """
    bwa mem -t ${task.cpus} -R "@RG\\tID:${meta.id}\\tSM:${meta.id}" ${ref} ${reads} \\
        | samtools view -b -o ${meta.id}.raw.bam -
    """
}
