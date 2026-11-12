SELECT r.run_id,
       r.folder || '/cohort.filtered.vcf.gz' AS file,
       o.sha256
FROM runs r
JOIN outputs o ON o.run_id = r.run_id
WHERE o.path LIKE '%cohort.filtered.vcf.gz';
