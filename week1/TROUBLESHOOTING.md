# Troubleshooting

## 1. The pipeline ran, printed nothing, and "succeeded"

I ran the pipeline and everything ran but there was no output and I was very confused so I looked to see my run_pipeline file in github and it was empty. I had forgotten to save my file on my code editor vs code. My code was never saved to my disk and therefore not uploaded to github. To fix this I saved the file in vs code and rerun the pipeline and thankfully everything ran correctly. 

## 2. `JOINT` used but never defined

Through differences in my coding I used 'JOINT' as a folder but I never defined it. For stage 6 and 7 from code I was looking at it utilized JOINT and that made sense to me as step 6 merges. To fix this I created a 'JOINT' file like 'QC', 'TRIM', ... This would have been a error that would have prevented my pipeline from completing. 


## Use of AI

I used Claude (Anthropic) to understand the assignment requirements, to explain
GATK and HaplotypeCaller, to help me understand the command structure for stages
3–7 (BWA-MEM, MarkDuplicates, HaplotypeCaller in GVCF mode, CombineGVCFs/
GenotypeGVCFs, VariantFiltration), and to help troubleshoot. It reviewed my script
and pointed out the undefined `JOINT` and `INDEX` variables, and it walked me
through diagnosing the empty-file problem with `echo $?` and `wc -l`. I ran every
command, made the edits, and checked the results myself.

## Other resources used

Broad Institute website for the tool GATK
https://gatk.broadinstitute.org/hc/en-us/articles/360035890431-The-logic-of-joint-calling-for-germline-short-variants

Broad Institue github for GATK
https://github.com/broadinstitute/gatk 

Demo code from canvas
