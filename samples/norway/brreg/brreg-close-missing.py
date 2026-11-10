#!/usr/bin/env python3
"""Close units StatBus still counts that a BRREG full file no longer lists.

A unit absent from the month's full file is gone from the register. When the
change feed reported its deletion, brreg-deletions-since.py already wrote it.
For the rest (owner decision, STATBUS-600 Q5) this writes one closure row per
unit: death_date = BRREG's slettedato when the unit lookup has one, otherwise
the 1st of the run month, and valid_from the 1st of the month containing the
day before the death, raised to the unit's first StatBus record. A unit whose
death falls on or before its first StatBus record cannot be closed and is
counted.

Reads from --work: <kind>.csv (the fitted full file), <kind>-gone.txt (units the
feed reported), alive-<kind>.txt (units StatBus counts), and known-legal-units.txt
or known-establishments.txt (organisasjonsnummer,first_valid_from).
Writes <kind>-missing-closures.csv and prints the counts as JSON.
"""
import argparse
import concurrent.futures
import csv
import datetime
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("feed", os.path.join(HERE, "brreg-deletions-since.py"))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)

KINDS = {"hovedenhet": ("enheter", "known-legal-units.txt"),
         "underenhet": ("underenheter", "known-establishments.txt")}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work", required=True)
    parser.add_argument("--run-month-start", required=True, type=datetime.date.fromisoformat)
    args = parser.parse_args()

    result = {}
    for kind, (register, known_name) in KINDS.items():
        path = lambda name: os.path.join(args.work, name)
        with open(path(f"{kind}.csv"), newline="", encoding="utf-8") as fitted:
            in_file = {row["organisasjonsnummer"] for row in csv.DictReader(fitted)}
        with open(path(f"{kind}-gone.txt"), encoding="utf-8") as gone_file:
            gone = {line.strip() for line in gone_file}
        first = {}
        with open(path(known_name), encoding="utf-8") as known_file:
            for line in known_file:
                if line.strip():
                    orgnr, start = line.strip().split(",")
                    first[orgnr] = datetime.date.fromisoformat(start)
        with open(path(f"alive-{kind}.txt"), encoding="utf-8") as alive_file:
            missing = sorted({o.strip() for o in alive_file if o.strip()} - in_file - gone)

        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            deaths = dict(zip(missing, pool.map(lambda o: feed.slettedato(register, o), missing)))
        counts = {"missing": len(missing), "with_slettedato": 0, "on_run_month_start": 0, "before_first_record": 0}
        with open(path(f"{kind}-missing-closures.csv"), "w", newline="", encoding="utf-8") as out:
            writer = csv.writer(out)
            writer.writerow(["tax_ident", "death_date", "valid_from", "valid_to"])
            for orgnr in missing:
                death = deaths[orgnr]
                if death:
                    counts["with_slettedato"] += 1
                else:
                    death = args.run_month_start
                    counts["on_run_month_start"] += 1
                valid_from = max((death - datetime.timedelta(days=1)).replace(day=1), first.get(orgnr, death))
                if death <= valid_from:
                    counts["before_first_record"] += 1
                    continue
                writer.writerow([orgnr, death.isoformat(), valid_from.isoformat(), "infinity"])
        result[kind] = counts
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
