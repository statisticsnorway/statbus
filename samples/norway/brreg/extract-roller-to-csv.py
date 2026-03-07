#!/usr/bin/env python3
"""
Extract org-to-org controlling relationships from BRREG roller JSON.

Reads tmp/roller.json.gz (streaming gzip + ijson for memory efficiency on ~2.8GB file),
filters to controlling role types where both orgs exist in enheter.csv,
deduplicates, and outputs tmp/roller_legal_relationships.csv.

Note: BRREG does not provide ownership percentages. The percentage column is
included in the CSV for schema compatibility but left empty.
"""

import csv
import gzip
import ijson
import sys
import os

# Role types that represent org-to-org relationships we import.
# HFOR, EIKM, KOMP are primary_influencer_only (form power groups).
# DTPR, DTSO are partnership roles (imported but don't form power groups).
# KENK and KDEB are excluded: KENK duplicates HFOR, KDEB duplicates KOMP.
CONTROLLING_ROLES = {'HFOR', 'DTPR', 'DTSO', 'EIKM', 'KOMP'}

WORKSPACE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.join(WORKSPACE, '..', '..', '..')
WORKSPACE = os.path.normpath(WORKSPACE)

ROLLER_JSON_GZ = os.path.join(WORKSPACE, 'tmp', 'roller.json.gz')
ENHETER_CSV = os.path.join(WORKSPACE, 'tmp', 'enheter.csv')
OUTPUT_CSV = os.path.join(WORKSPACE, 'tmp', 'roller_legal_relationships.csv')


def load_enheter_orgnums(path):
    """Read organisasjonsnummer from enheter.csv into a set."""
    orgnums = set()
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            orgnums.add(row['organisasjonsnummer'])
    print(f"Loaded {len(orgnums)} org numbers from enheter.csv")
    return orgnums


def extract_relationships(roller_path, enheter_orgnums):
    """Extract relationships using ijson streaming parser (memory efficient)."""
    relationships = set()
    total_orgs = 0

    with gzip.open(roller_path, 'rb') as f:
        # Stream through top-level array items
        for org in ijson.items(f, 'item'):
            total_orgs += 1
            if total_orgs % 100000 == 0:
                print(f"  Processed {total_orgs} orgs, found {len(relationships)} relationships so far...")

            influenced_orgnum = org.get('organisasjonsnummer')
            if not influenced_orgnum:
                continue

            rollegrupper = org.get('rollegrupper', [])
            if not rollegrupper:
                continue

            for gruppe in rollegrupper:
                roller = gruppe.get('roller', [])
                for rolle in roller:
                    rolle_type = rolle.get('type', {})
                    rolle_kode = rolle_type.get('kode', '')

                    if rolle_kode not in CONTROLLING_ROLES:
                        continue

                    # Only org-to-org relationships (skip person relationships)
                    enhet = rolle.get('enhet')
                    if not enhet:
                        continue

                    influencing_orgnum = enhet.get('organisasjonsnummer')
                    if not influencing_orgnum:
                        continue

                    # Skip if resigned
                    if rolle.get('fratraadt', False):
                        continue

                    # Record the relationship tuple for deduplication
                    # No percentage — BRREG doesn't provide ownership percentages
                    relationships.add((
                        influencing_orgnum,
                        influenced_orgnum,
                        rolle_kode,
                    ))

    return relationships, total_orgs


def main():
    if not os.path.exists(ROLLER_JSON_GZ):
        print(f"Error: {ROLLER_JSON_GZ} not found. Run download-to-tmp.sh first.")
        sys.exit(1)

    if not os.path.exists(ENHETER_CSV):
        print(f"Error: {ENHETER_CSV} not found. Run download-to-tmp.sh first.")
        sys.exit(1)

    # Load enheter org numbers for filtering
    enheter_orgnums = load_enheter_orgnums(ENHETER_CSV)

    print(f"Extracting relationships from {ROLLER_JSON_GZ} (streaming gzip + ijson)...")
    relationships, total_orgs = extract_relationships(ROLLER_JSON_GZ, enheter_orgnums)

    print(f"Total orgs processed: {total_orgs}")
    print(f"Total controlling org-to-org relationships found: {len(relationships)}")

    # Filter to only relationships where BOTH orgs exist in enheter.csv
    filtered = sorted(
        (r for r in relationships if r[0] in enheter_orgnums and r[1] in enheter_orgnums),
        key=lambda r: (r[0], r[1], r[2])
    )
    print(f"After filtering to orgs in enheter.csv: {len(filtered)} relationships")

    # Write output CSV — percentage column kept for schema compatibility but empty
    with open(OUTPUT_CSV, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['influencing_tax_ident', 'influenced_tax_ident', 'rel_type_code', 'percentage'])
        for row in filtered:
            writer.writerow(list(row) + [''])

    print(f"Output written to {OUTPUT_CSV}")


if __name__ == '__main__':
    main()
