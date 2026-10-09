include { VALIDATE        } from './modules/validate.nf'
include { FASTQC          } from './modules/fastqc.nf'
include { FASTP           } from './modules/fastp.nf'
include { BWA_MEM         } from './modules/bwa_mem.nf'
include { MARKDUPLICATES  } from './modules/markduplicates.nf'
include { HAPLOTYPECALLER } from './modules/haplotypecaller.nf'
include { JOINT_GENOTYPE  } from './modules/joint_genotype.nf'
include { FILTER          } from './modules/filter.nf'
include { MULTIQC         } from './modules/multiqc.nf'
include { PUBLISH         } from './modules/publish.nf'

workflow {
    main:
    // the samplesheet, one item per sample: [meta, reads]
    sheet = file(params.samplesheet)
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample_id, single_end: row.library_type == 'single']
            def r1 = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
            [meta, reads]
        }

    // the reference: value channels, read by every sample
    ref       = file(params.ref)
    ref_index = files("${params.ref}.*")
    ref_dict  = file("${ref.parent}/${ref.baseName}.dict")

    // stage 0, then every sample waits for it
    VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(),
             ref, ref_index, ref_dict)

    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }

    // stages 1-5, once per sample
    FASTQC(ch_checked)
    FASTP(ch_checked)
    BWA_MEM(FASTP.out.reads, ref, ref_index)
    MARKDUPLICATES(BWA_MEM.out)
    HAPLOTYPECALLER(MARKDUPLICATES.out, ref, ref_index, ref_dict)

    // stages 6-7, once for the cohort
    JOINT_GENOTYPE(HAPLOTYPECALLER.out.gvcf.collect(), HAPLOTYPECALLER.out.tbi.collect(),
                   ref, ref_index, ref_dict)
    FILTER(JOINT_GENOTYPE.out, ref, ref_index, ref_dict)

    // stage 8: every QC report at once
    MULTIQC(FASTQC.out.mix(FASTP.out.json).collect())

    // stage 9: the manifest and samples.tsv
    PUBLISH(VALIDATE.out.sheet, FILTER.out.vcf.mix(FILTER.out.table, MULTIQC.out).collect())

    publish:
    vcf      = FILTER.out.vcf
    variants = FILTER.out.table
    multiqc  = MULTIQC.out
    manifest = PUBLISH.out.manifest
    samples  = PUBLISH.out.samples
}

output {
    vcf {
        path '.'
    }
    variants {
        path '.'
    }
    multiqc {
        path '.'
    }
    manifest {
        path '.'
    }
    samples {
        path '.'
    }
}
