-- A database of pipeline runs: one row per pipeline version, run, sample,
-- sample-in-a-run, variant and output file.

CREATE TABLE pipelines (
    pipeline_id    INTEGER PRIMARY KEY,
    name           TEXT NOT NULL,
    version        TEXT NOT NULL,
    implementation TEXT NOT NULL,          -- nextflow or snakemake
    UNIQUE (name, version, implementation)
) STRICT;

CREATE TABLE runs (
    run_id      TEXT PRIMARY KEY,          -- the manifest's pipeline.run_id
    pipeline_id INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    started_at  TEXT,
    finished_at TEXT,
    exit_status TEXT,
    platform    TEXT,                      -- platform.kind
    executor    TEXT,
    samplesheet TEXT,
    reference   TEXT,
    region      TEXT,
    folder      TEXT                       -- absolute path of the run's folder
) STRICT;

CREATE TABLE samples (
    sample_id              TEXT PRIMARY KEY,
    sex                    TEXT,
    population             TEXT,
    family                 TEXT,
    father                 TEXT,
    mother                 TEXT,
    phenotype              TEXT,
    is_synthetic_phenotype TEXT            -- kept as written in the file
) STRICT;

CREATE TABLE run_samples (
    run_id       TEXT NOT NULL REFERENCES runs (run_id),
    sample_id    TEXT NOT NULL REFERENCES samples (sample_id),
    condition    TEXT,
    library_type TEXT,
    PRIMARY KEY (run_id, sample_id)        -- a sample once per run
) STRICT;

CREATE TABLE variants (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    chrom  TEXT NOT NULL,
    pos    INTEGER NOT NULL,
    ref    TEXT NOT NULL,
    alt    TEXT NOT NULL,
    qual   REAL,
    filter TEXT
) STRICT;

CREATE TABLE outputs (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    path   TEXT NOT NULL,
    sha256 TEXT NOT NULL,                  -- the 64 hex characters, without "sha256:"
    PRIMARY KEY (run_id, path)
) STRICT;
