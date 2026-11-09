#!/usr/bin/env python3
"""Write the BRREG deletions since a point in time as a StatBus import file.

BRREG's change feed (data.brreg.no/enhetsregisteret/api/oppdateringer/<register>)
lists every change with an increasing oppdateringsid. A unit whose last change in
the window is "Sletting" has left the register; its slettedato comes from the unit
lookup. The output is a CSV for the *_source_dates import definitions: one row per
deleted unit that StatBus already has, with

    tax_ident  = organisasjonsnummer
    death_date = slettedato
    valid_from = the 1st of the month containing (slettedato - 1 day)
    valid_to   = infinity

valid_from sits before the death so the record the row writes starts before the
unit dies, which the date_consistency import step requires.

A deleted unit StatBus does not have (born and deleted inside the window) is
counted, not written: a row for an unknown unit carries no name and stops the
import job for review.

Usage:
  brreg-deletions-since.py --register enheter|underenheter --since 2026-11-01 \
      --known known-idents.txt --out deletions.csv [--state state.json]

  --since    ISO date; the feed is read from 00:00 UTC that day.
  --known    file with one organisasjonsnummer per line that StatBus already has.
  --state    optional JSON file; receives counts and the last oppdateringsid read.
"""
import argparse
import csv
import datetime
import json
import sys
import time
import urllib.error
import urllib.request

API = "https://data.brreg.no/enhetsregisteret/api"
EMBEDDED_KEY = {"enheter": "oppdaterteEnheter", "underenheter": "oppdaterteUnderenheter"}
PAGE_SIZE = 10000  # the feed refuses size * (page + 1) > 10000; page by oppdateringsid instead


def fetch_json(url, attempts=5):
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 410:
                return {"_gone": True}
            if error.code < 500 or attempt == attempts:
                raise
        except urllib.error.URLError:
            if attempt == attempts:
                raise
        time.sleep(5 * attempt)
    raise RuntimeError("unreachable")


def last_change_per_unit(register, since):
    """Return {organisasjonsnummer: endringstype of its last change}, and the last id read."""
    key = EMBEDDED_KEY[register]
    last = {}
    url = f"{API}/oppdateringer/{register}?dato={since}T00:00:00.000Z&size={PAGE_SIZE}"
    last_id = None
    while True:
        page = fetch_json(url)
        items = page.get("_embedded", {}).get(key, [])
        for item in items:
            last[item["organisasjonsnummer"]] = item["endringstype"]
            last_id = item["oppdateringsid"]
        if len(items) < PAGE_SIZE:
            return last, last_id
        url = f"{API}/oppdateringer/{register}?oppdateringsid={last_id + 1}&size={PAGE_SIZE}"


def slettedato(register, orgnr):
    unit = fetch_json(f"{API}/{register}/{orgnr}")
    if unit.get("_gone"):
        return None
    value = unit.get("slettedato")
    return datetime.date.fromisoformat(value) if value else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--register", required=True, choices=sorted(EMBEDDED_KEY))
    parser.add_argument("--since", required=True, type=datetime.date.fromisoformat)
    parser.add_argument("--known", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--state")
    args = parser.parse_args()

    with open(args.known, encoding="utf-8") as known_file:
        known = {line.strip() for line in known_file if line.strip()}

    last, last_id = last_change_per_unit(args.register, args.since.isoformat())
    deleted = sorted(orgnr for orgnr, change in last.items() if change == "Sletting")
    removed = sorted(orgnr for orgnr, change in last.items() if change == "Fjernet")

    counts = {"changed_units": len(last), "deleted": len(deleted), "removed_fjernet": len(removed),
              "deleted_unknown_to_statbus": 0, "deleted_without_slettedato": 0, "written": 0}
    with open(args.out, "w", newline="", encoding="utf-8") as out_file:
        writer = csv.writer(out_file)
        writer.writerow(["tax_ident", "death_date", "valid_from", "valid_to"])
        for orgnr in deleted:
            if orgnr not in known:
                counts["deleted_unknown_to_statbus"] += 1
                continue
            death = slettedato(args.register, orgnr)
            if death is None:
                counts["deleted_without_slettedato"] += 1
                continue
            valid_from = (death - datetime.timedelta(days=1)).replace(day=1)
            writer.writerow([orgnr, death.isoformat(), valid_from.isoformat(), "infinity"])
            counts["written"] += 1

    counts["last_oppdateringsid"] = last_id
    print(json.dumps({"register": args.register, "since": args.since.isoformat(), **counts}))
    if args.state:
        with open(args.state, "w", encoding="utf-8") as state_file:
            json.dump({"register": args.register, "since": args.since.isoformat(), **counts}, state_file)
    return 0


if __name__ == "__main__":
    sys.exit(main())
