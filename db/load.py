#!/usr/bin/env python3
"""Load pipeline runs into the database that db/schema.sql builds.

usage: python3 db/load.py runs.db db/variant-call-cohort.tsv RUN_FOLDER [RUN_FOLDER ...]

Each run goes in whole or not at all. A run already in the database is skipped,
so loading twice changes nothing.
"""
import csv
import json
import os
import sqlite3
import sys

META_COLS = ["sample_id", "sex", "population", "family", "father", "mother",
             "phenotype", "is_synthetic_phenotype"]


def number(value, kind):
    """Convert a TSV value to int or float; an empty value or '.' becomes NULL."""
    if value is None or value.strip() in ("", "."):
        return None
    return kind(value)


def sample_exists(con, sample_id):
    return con.execute("SELECT 1 FROM samples WHERE sample_id = ?",
                       (sample_id,)).fetchone() is not None


def load_metadata(con, path):
    """Copy the metadata file into samples; lines starting with # are notes."""
    with open(path, newline="") as f:
        lines = [line for line in f if not line.startswith("#")]
    added = 0
    with con:
        for row in csv.DictReader(lines, delimiter="\t"):
            if sample_exists(con, row["sample_id"]):
                continue
            con.execute(
                f"INSERT INTO samples ({', '.join(META_COLS)}) "
                f"VALUES ({', '.join('?' * len(META_COLS))})",
                [row.get(c) for c in META_COLS])
            added += 1
    print(f"metadata: {added} sample(s) added")


def load_run(con, folder):
    with open(os.path.join(folder, "manifest.json")) as f:
        m = json.load(f)
    pipe, params, plat = m["pipeline"], m.get("params", {}), m.get("platform", {})
    run_id = pipe["run_id"]

    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        print(f"{folder}: run {run_id} is already loaded, skipped")
        return

    with con:  # commits at the end, or undoes the whole run on any error
        key = (pipe["name"], pipe["version"], pipe["implementation"])
        row = con.execute("SELECT pipeline_id FROM pipelines "
                          "WHERE name = ? AND version = ? AND implementation = ?",
                          key).fetchone()
        if row:
            pipeline_id = row[0]
        else:
            pipeline_id = con.execute("INSERT INTO pipelines (name, version, implementation) "
                                      "VALUES (?, ?, ?)", key).lastrowid

        con.execute(
            "INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status, "
            "platform, executor, samplesheet, reference, region, folder) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (run_id, pipeline_id, pipe.get("started_at"), pipe.get("finished_at"),
             pipe.get("exit_status"), plat.get("kind"), plat.get("executor"),
             params.get("samplesheet"), params.get("ref"), params.get("region"),
             os.path.abspath(folder)))

        for s in m["samples"]:
            if not sample_exists(con, s["sample_id"]):
                con.execute("INSERT INTO samples (sample_id) VALUES (?)", (s["sample_id"],))
            con.execute("INSERT INTO run_samples (run_id, sample_id, condition, library_type) "
                        "VALUES (?, ?, ?, ?)",
                        (run_id, s["sample_id"], s.get("condition"), s.get("library_type")))

        n_variants = 0
        with open(os.path.join(folder, "variants.tsv"), newline="") as f:
            for v in csv.DictReader(f, delimiter="\t"):
                con.execute("INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?)",
                            (run_id, v["chrom"], number(v["pos"], int), v["ref"], v["alt"],
                             number(v["qual"], float), v["filter"]))
                n_variants += 1

        for o in m.get("outputs", []):
            checksum = o["checksum"].removeprefix("sha256:")
            con.execute("INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
                        (run_id, o["path"], checksum))

    print(f"{folder}: run {run_id} loaded: {len(m['samples'])} samples, "
          f"{n_variants} variants, {len(m.get('outputs', []))} outputs")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    db, metadata, folders = sys.argv[1], sys.argv[2], sys.argv[3:]
    con = sqlite3.connect(db)
    con.execute("PRAGMA foreign_keys = ON")
    load_metadata(con, metadata)
    failed = 0
    for folder in folders:
        try:
            load_run(con, folder)
        except (sqlite3.Error, OSError, KeyError, ValueError) as e:
            print(f"{folder}: refused, nothing loaded: {e}", file=sys.stderr)
            failed += 1
    con.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
