#!/usr/bin/env python3
"""Generate test/data/318_albania_legal_units.csv and 318_albania_establishments.csv.

Test 404 (test/sql/404_regression_albania_import.sql) needs Albania-shaped
import files: the same columns, row count, date formats, duplicate rows per
unit, establishment-to-legal-unit links and the handful of rows that trigger
specific import errors. It does not need any real firm. This script turns the
source extract into such files and is the record of how every column was made;
see test/data/README.md for the provenance.

Run from the repository root with the source files as arguments:
    python3 test/data/318_albania_generate.py SOURCE_LEGAL_UNITS.csv SOURCE_ESTABLISHMENTS.csv
It writes the two test files in place. The source extract is not kept in the
repository.

Per column:
- Replaced by a generated value of the same shape (letters stay letters,
  digits stay digits, punctuation kept), one source value always giving the
  same generated value: tax identifiers (one mapping shared by both files, so
  links survive), names, address lines, post places, phone, landline,
  mobile, fax.
- Replaced by a numbered placeholder: e-mail (unitNNN@example.org) and web
  address (www.unitNNN.example.org).
- Replaced by a generated number of the same digit count: employees,
  turnover, male, female, selfemp, punpag.
- Shuffled between units: primary and secondary activity, region, legal
  form and sector move together as one set from one legal unit to another
  (and between establishments), so no unit keeps its own combination.
- Kept: valid_from, valid_to, birth_date (already synthetic in the source:
  1 January of years up to 2315), country codes, coordinates, data source,
  status and unit size codes, empty cells and row order. Rows that the test
  asserts on (foreign units with a region, the out-of-range latitude, rows
  without identifiers or dates) keep their codes so the same errors occur.
"""
import csv, hashlib, random, sys

OUT_LU = "test/data/318_albania_legal_units.csv"
OUT_EST = "test/data/318_albania_establishments.csv"
maps = {}


def same_shape(v, salt, attempt=0):
    h = random.Random(hashlib.sha256(f"{salt}|{attempt}|{v}".encode()).hexdigest())
    out = []
    for ch in v:
        if ch.isdigit():
            out.append(str(h.randrange(10)))
        elif ch.isalpha():
            c = chr(ord("a") + h.randrange(26))
            out.append(c.upper() if ch.isupper() else c)
        else:
            out.append(ch)
    return "".join(out)


def mapped(kind, v, make, unique=True):
    if v == "":
        return v
    m = maps.setdefault(kind, {})
    if v not in m:
        used = set(m.values())
        new, attempt = make(v, len(m), 0), 0
        while unique and new in used:
            attempt += 1
            new = make(v, len(m), attempt)
            if attempt > 1000:
                raise SystemExit(f"cannot find a free {kind} value")
        m[v] = new
    return m[v]


def shaped(kind, unique=True):
    return lambda v: mapped(kind, v, lambda x, n, a: same_shape(x, kind, a), unique)


tax = shaped("tax")
email = lambda v: mapped("email", v, lambda x, n, a: f"unit{n + 1:03d}@example.org" if "@" in x else same_shape(x, "email", a))
web = lambda v: mapped("web", v, lambda x, n, a: f"www.unit{n + 1:03d}.example.org")

LU_REPLACE = {
    "tax_ident": tax, "name": shaped("name"),
    "physical_address_part1": shaped("addr"), "physical_address_part2": shaped("addr"),
    "physical_address_part3": shaped("addr"), "postal_address_part1": shaped("addr"),
    "postal_address_part2": shaped("addr"), "postal_address_part3": shaped("addr"),
    "physical_postplace": shaped("place"), "postal_postplace": shaped("place"),
    "phone_number": shaped("phone"), "landline": shaped("phone"),
    "mobile_number": shaped("phone"), "fax_number": shaped("phone"),
    "web_address": web, "email_address": email,
    "employees": shaped("emp", False), "turnover": shaped("turnover", False),
    "male": shaped("male", False), "female": shaped("female", False),
    "selfemp": shaped("selfemp", False), "punpag": shaped("punpag", False),
}
EST_REPLACE = {"legal_unit_tax_ident": tax, "tax_ident": tax, "name": tax, "employees": shaped("emp", False)}

LU_CODES = ["primary_activity_category_code", "secondary_activity_category_code",
            "physical_region_code", "legal_form_code", "sector_code"]
EST_CODES = ["primary_activity_category_code", "secondary_activity_category_code", "physical_region_code"]


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f.read().splitlines()))
    return rows[0], rows[1:]


def write(path, header, body):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(body)
    print(f"{path}: {len(body)} rows")


def shuffle_codes(header, body, cols, key_col, pinned):
    """Give each unit (rows sharing key_col) the code set of another unit.

    Units are only swapped with units whose codes are empty in the same
    places, so a missing code stays missing (the import treats it apart)."""
    idx = {c: header.index(c) for c in cols + [key_col]}
    first = {}
    for r in body:
        first.setdefault(r[idx[key_col]], tuple(r[idx[c]] for c in cols))
    groups = {}
    for k, codes in first.items():
        if k and k not in pinned:
            groups.setdefault(tuple(v == "" for v in codes), []).append(k)
    new_codes = {}
    rng = random.Random(318)
    for units in groups.values():
        donors = units[:]
        rng.shuffle(donors)
        new_codes.update({u: first[d] for u, d in zip(units, donors)})
    for r in body:
        k = r[idx[key_col]]
        if k in new_codes:
            for c, v in zip(cols, new_codes[k]):
                r[idx[c]] = v


def main(src_lu, src_est):
    lu_h, lu = read(src_lu)
    es_h, es = read(src_est)
    li = {c: i for i, c in enumerate(lu_h)}
    # Units the test asserts on keep their codes: foreign units with a region,
    # the out-of-range latitude, and rows without a tax identifier.
    pinned = {r[li["tax_ident"]] for r in lu
              if r[li["physical_country_iso_2"]] not in ("AL", "")
              or (r[li["latitude"]] and abs(float(r[li["latitude"]])) > 90)}
    pinned.add("")
    shuffle_codes(lu_h, lu, LU_CODES, "tax_ident", pinned)
    shuffle_codes(es_h, es, EST_CODES, "tax_ident", {""})
    for header, body, replace in ((lu_h, lu, LU_REPLACE), (es_h, es, EST_REPLACE)):
        ix = {c: i for i, c in enumerate(header)}
        for r in body:
            for col, fn in replace.items():
                r[ix[col]] = fn(r[ix[col]])
    write(OUT_LU, lu_h, lu)
    write(OUT_EST, es_h, es)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
