#!/usr/bin/env python3
"""Fit a BRREG CSV download to an import definition's source columns, by name.

BRREG adds columns to its downloads over time (enheter.csv grew from 68 to 90
columns between April and November 2026, and the order changed). An import job
loads its upload table by position, so the file is rewritten to exactly the
definition's source columns, in the definition's order. A column the
definition lists but the file lacks is written empty; a column the file has
but the definition does not list is dropped and named on stderr.

For legal units (--derive-status) the loader also writes status_code, the
StatBus status derived from BRREG's flags (owner decision, STATBUS-600 Q3b):
"passive" when konkurs, underAvvikling or
underTvangsavviklingEllerTvangsopplosning is true, otherwise "active". This is a
bridge until import definitions can derive values themselves (STATBUS-601).

Usage:
  brreg-fit-csv.py --columns columns.txt --in enheter.csv --out fitted.csv
      [--derive-status] [--only-parents enheter.csv]

  --columns       the definition's source column names, one per line, in priority order.
  --only-parents  keep only rows whose overordnetEnhet is an organisasjonsnummer in that
                  file (establishments whose legal unit is in the legal unit file).
"""
import argparse
import collections
import csv
import json
import sys

PASSIVE_FLAGS = ("konkurs", "underAvvikling", "underTvangsavviklingEllerTvangsopplosning")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--columns", required=True)
    parser.add_argument("--in", dest="source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--derive-status", action="store_true")
    parser.add_argument("--only-parents")
    args = parser.parse_args()

    with open(args.columns, encoding="utf-8") as columns_file:
        columns = [line.strip() for line in columns_file if line.strip()]

    parents = None
    if args.only_parents:
        with open(args.only_parents, newline="", encoding="utf-8") as parent_file:
            parents = {row["organisasjonsnummer"] for row in csv.DictReader(parent_file)}

    counts = collections.Counter()
    with open(args.source, newline="", encoding="utf-8") as source_file, \
            open(args.out, "w", newline="", encoding="utf-8") as out_file:
        reader = csv.DictReader(source_file)
        present = set(reader.fieldnames)
        derived = {"status_code"} if args.derive_status else set()
        missing = [c for c in columns if c not in present and c not in derived]
        dropped = [c for c in reader.fieldnames if c not in columns]
        if args.derive_status:
            absent_flags = [f for f in PASSIVE_FLAGS if f not in present]
            if absent_flags:
                sys.exit(f"brreg-fit-csv: status flags missing from {args.source}: {absent_flags}")
        writer = csv.writer(out_file, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(columns)
        for row in reader:
            if parents is not None and row.get("overordnetEnhet") not in parents:
                counts["skipped_without_parent"] += 1
                continue
            if args.derive_status:
                passive = any(row.get(flag, "").lower() == "true" for flag in PASSIVE_FLAGS)
                row["status_code"] = "passive" if passive else "active"
                counts["status_" + row["status_code"]] += 1
            writer.writerow([row.get(c, "") for c in columns])
            counts["rows"] += 1

    report = {"file": args.source, **counts, "missing_columns": missing, "dropped_columns": dropped}
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
