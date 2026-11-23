#!/usr/bin/env python3
"""Generate test/data/341_duplicate_tax_ident_big_file.csv.

Test 341 checks that an import refuses rows sharing a tax identifier and
imports the rest. It needs the duplicate pattern (which rows share an
identifier, which have none), not any real firm. Its source was a list of
600 Moroccan company and person names with statistical and tax identifiers;
see test/data/README.md for the provenance. This script is the record of how
each column was made. (Test 340's small file uses the invented demo names
and needs no generation.)

Run from the repository root with the source file as argument:
    python3 test/data/341_duplicate_ident_generate.py SOURCE_341.csv
It writes the test file in place. The source file is not kept.

Per column:
- name: "Unit NNN" numbered in row order of first appearance; a name that
  appears twice gets the same number.
- stat_ident, tax_ident: a generated number of the same digit count, one
  source value always giving the same generated value, so every duplicate
  and every empty cell stays where it was. Values of up to two digits
  (such as the deliberate duplicate "01") are kept: they identify nobody.
"""
import csv, hashlib, random, sys

OUT = ["test/data/341_duplicate_tax_ident_big_file.csv"]
maps = {}


def digits(v, kind):
    if len(v) <= 2:
        return v
    m = maps.setdefault(kind, {})
    if v not in m:
        used, attempt = set(m.values()), 0
        while True:
            h = random.Random(hashlib.sha256(f"{kind}|{attempt}|{v}".encode()).hexdigest())
            new = str(h.randrange(1, 10)) + "".join(str(h.randrange(10)) for _ in range(len(v) - 1))
            if new not in used:
                break
            attempt += 1
        m[v] = new
    return m[v]


def name(v):
    m = maps.setdefault("name", {})
    if v not in m:
        m[v] = f"Unit {len(m) + 1:03d}"
    return m[v]


def main(*sources):
    for src, out in zip(sources, OUT):
        with open(src, encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))
        for r in rows:
            r["name"] = name(r["name"]) if r["name"] else ""
            r["stat_ident"] = digits(r["stat_ident"], "stat") if r["stat_ident"] else ""
            r["tax_ident"] = digits(r["tax_ident"], "tax") if r["tax_ident"] else ""
        with open(out, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["name", "stat_ident", "tax_ident"], lineterminator="\n")
            w.writeheader()
            w.writerows(rows)
        print(f"{out}: {len(rows)} rows")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
