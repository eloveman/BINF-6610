configfile: "config.yaml"

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

import csv
import os
import re

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]                                                     # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                           # smoke.dict, not smoke.fa.dict

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) if names else "(?!)"


rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


# ---- stage 0 · validate ----------------------------------------------------
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"


# ---- stage 1 · qc_raw ------------------------------------------------------
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    threads: 4
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -t {threads} -o {output} {input.reads}"
        " && ls {output}/*_fastqc.zip > /dev/null) 2> {log}"


# ---- stage 2 · trim --------------------------------------------------------
# Two rules: a paired sample makes two trimmed files, a single-end one makes one.
# wildcard_constraints send each sample to exactly one of them.
rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "(fastp -w {threads} -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2}"
        " -j {output.json} -h {output.html}"
        " && test $(gzip -dc {output.r1} | wc -l) -gt 0) 2> {log}"


rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "(fastp -w {threads} -i {input.r1} -o {output.r1} -j {output.json} -h {output.html}"
        " && test $(gzip -dc {output.r1} | wc -l) -gt 0) 2> {log}"


def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]


# ---- stage 3 · align -------------------------------------------------------
# One rule: {input.reads} is one file or two, from trimmed().
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        index=REF_BWA,
    output:
        bam="work/align/{sample}.raw.bam",
    threads: 8
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}' {input.ref} {input.reads} \
            | samtools view -@ {threads} -b -o {output.bam} - \
         && {BIN}/check_mapped.sh {output.bam} 50) 2> {log}
        """


# ---- stage 4 · postprocess -------------------------------------------------
rule markduplicates:
    input:
        bam="work/align/{sample}.raw.bam",
    output:
        sorted=temp("work/markdup/{sample}.sorted.bam"),
        bam="work/markdup/{sample}.bam",
        bai="work/markdup/{sample}.bam.bai",
        metrics="work/markdup/{sample}.markdup.txt",
        flagstat="work/markdup/{sample}.flagstat.txt",
    threads: 4
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        "(samtools sort -@ {threads} -T {resources.tmpdir}/{wildcards.sample}.sort"
        " -o {output.sorted} {input.bam}"
        " && gatk MarkDuplicates -I {output.sorted} -O {output.bam} -M {output.metrics}"
        " --VALIDATION_STRINGENCY SILENT --TMP_DIR {resources.tmpdir}"
        " && samtools index -@ {threads} {output.bam}"
        " && samtools flagstat {output.bam} > {output.flagstat}) > {log} 2>&1"


# ---- stage 5 · quantify ----------------------------------------------------
rule haplotypecaller:
    input:
        bam="work/markdup/{sample}.bam",
        bai="work/markdup/{sample}.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    params:
        region=config["region"],
    threads: 8
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        "gatk HaplotypeCaller -R {input.ref} -I {input.bam} -L {params.region} -ERC GVCF"
        " --native-pair-hmm-threads {threads} --tmp-dir {resources.tmpdir}"
        " -O {output.gvcf} > {log} 2>&1"


# ---- stage 6 · merge -------------------------------------------------------
# expand() lists every sample's GVCF, so this waits for all of them.
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        combined="work/joint/cohort.g.vcf.gz",
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        region=config["region"],
        n=len(SAMPLES),
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        "(gatk CombineGVCFs -R {input.ref} {params.variants} -L {params.region}"
        " --tmp-dir {resources.tmpdir} -O {output.combined}"
        " && gatk GenotypeGVCFs -R {input.ref} -V {output.combined} -L {params.region}"
        " --tmp-dir {resources.tmpdir} -O {output.vcf}"
        " && test $(bcftools query -l {output.vcf} | wc -l) -eq {params.n}) > {log} 2>&1"


# ---- stage 7 · analyze -----------------------------------------------------
# Hard filters label failing sites, they don't remove them.
rule filter:
    input:
        vcf=rules.joint_genotype.output.vcf,
        tbi=rules.joint_genotype.output.tbi,
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk VariantFiltration -R {input.ref} -V {input.vcf} \
             --filter-expression "QD < 2.0"  --filter-name "QD2" \
             --filter-expression "FS > 60.0" --filter-name "FS60" \
             --filter-expression "MQ < 40.0" --filter-name "MQ40" \
             --filter-expression "SOR > 3.0" --filter-name "SOR3" \
             --tmp-dir {resources.tmpdir} \
             -O {output.vcf} \
         && test $(bcftools view -H {output.vcf} | wc -l) -gt 0 \
         && printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table} \
         && bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}) > {log} 2>&1
        """


# ---- stage 8 · qc_report ---------------------------------------------------
# Given the reports, not a folder: MultiQC reads exactly these.
rule multiqc:
    input:
        fastqc=expand("work/fastqc/{sample}", sample=SAMPLES),
        fastp=expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        markdup=expand("work/markdup/{sample}.markdup.txt", sample=SAMPLES),
        flagstat=expand("work/markdup/{sample}.flagstat.txt", sample=SAMPLES),
    output:
        report=f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input}"
        " && cp work/multiqc/multiqc_report.html {output.report}) > {log} 2>&1"


# ---- stage 9 · publish -----------------------------------------------------
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
