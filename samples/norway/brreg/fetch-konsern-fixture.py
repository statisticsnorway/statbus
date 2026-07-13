#!/usr/bin/env python3
"""Build a cross-border power-group fixture from a BRREG konsernstruktur CSV.

STATBUS-121: a real Norwegian konsern (Aker Solutions ASA, org 913748174)
contains many "Utenlandsk enhet" (UTLA = foreign) members. The legal_relationship
import step drops any edge whose endpoint tax_ident is not already a legal_unit
(import.analyse_legal_relationship: unknown_influencing/unknown_influenced ->
state='error', action='skip'). So the foreign members must be materialized as
legal_units FIRST, via the ordinary hovedenhet (enheter) import, which maps
forretningsadresse.landkode -> physical_country_iso_2. A UTLA enhet record
carries its foreign country there (e.g. AKER SOLUTIONS KOREA -> "KR").

This script reads a konsernstruktur CSV (as returned by
  https://data.brreg.no/enhetsregisteret/api/konsernstruktur/{orgnr}/csv ),
fetches each member's full enhet record from the BRREG open API, and emits two
committed, hermetic fixtures that plug straight into brreg-import-selection.sh:

  samples/norway/legal_unit/konsern-enheter.csv       (hovedenhet upload format)
  samples/norway/legal_relationship/konsern-roller.csv (roller upload format)

Run once; commit the CSVs. Tests load the committed CSVs (no network).

Usage:
  python3 samples/norway/brreg/fetch-konsern-fixture.py tmp/konsern_aker.csv
"""
import csv
import io
import json
import sys
import time
import urllib.request
from pathlib import Path

ENHET_API = "https://data.brreg.no/enhetsregisteret/api/enheter/{}"

# The exact 54-column hovedenhet upload header (must match
# samples/norway/legal_unit/enheter-selection.csv so \copy targets the same
# upload table). Order is load-bearing.
ENHETER_HEADER = [
    "organisasjonsnummer", "navn",
    "organisasjonsform.kode", "organisasjonsform.beskrivelse",
    "naeringskode1.kode", "naeringskode1.beskrivelse",
    "naeringskode2.kode", "naeringskode2.beskrivelse",
    "naeringskode3.kode", "naeringskode3.beskrivelse",
    "hjelpeenhetskode.kode", "hjelpeenhetskode.beskrivelse",
    "harRegistrertAntallAnsatte", "antallAnsatte", "hjemmeside",
    "postadresse.adresse", "postadresse.poststed", "postadresse.postnummer",
    "postadresse.kommune", "postadresse.kommunenummer",
    "postadresse.land", "postadresse.landkode",
    "forretningsadresse.adresse", "forretningsadresse.poststed",
    "forretningsadresse.postnummer", "forretningsadresse.kommune",
    "forretningsadresse.kommunenummer",
    "forretningsadresse.land", "forretningsadresse.landkode",
    "institusjonellSektorkode.kode", "institusjonellSektorkode.beskrivelse",
    "sisteInnsendteAarsregnskap", "registreringsdatoenhetsregisteret",
    "stiftelsesdato", "registrertIMvaRegisteret",
    "frivilligMvaRegistrertBeskrivelser", "registrertIFrivillighetsregisteret",
    "registrertIForetaksregisteret", "registrertIStiftelsesregisteret",
    "konkurs", "konkursdato", "underAvvikling", "underAvviklingDato",
    "underTvangsavviklingEllerTvangsopplosning",
    "tvangsopplostPgaManglendeDagligLederDato",
    "tvangsopplostPgaManglendeRevisorDato",
    "tvangsopplostPgaManglendeRegnskapDato",
    "tvangsopplostPgaMangelfulltStyreDato",
    "tvangsavvikletPgaManglendeSlettingDato",
    "overordnetEnhet", "maalform", "vedtektsdato",
    "vedtektsfestetFormaal", "aktivitet",
]

# konsern controlling (>50% ownership / konsern datter) maps to HFOR
# (Hovedforetak = parent company), the primary power-group relationship
# (public.legal_rel_type: HFOR is primary_influencer_only=TRUE). A konsern is a
# tree, so each member has exactly one HFOR parent -> primary_influencer_only holds.
REL_TYPE_CODE = "HFOR"


def _get(d, *path):
    for p in path:
        if not isinstance(d, dict):
            return None
        d = d.get(p)
    return d


def _addr_line(addr):
    if not isinstance(addr, dict):
        return ""
    parts = addr.get("adresse") or []
    if isinstance(parts, str):
        parts = [parts]
    return ", ".join(p for p in parts if p)


def _bool(v):
    if v is True:
        return "true"
    if v is False:
        return "false"
    return ""


def enhet_row(d):
    naering = d.get("naeringskode1") or {}
    naering2 = d.get("naeringskode2") or {}
    naering3 = d.get("naeringskode3") or {}
    orgform = d.get("organisasjonsform") or {}
    hjelp = d.get("hjelpeenhetskode") or {}
    post = d.get("postadresse") or {}
    forr = d.get("forretningsadresse") or {}
    sektor = d.get("institusjonellSektorkode") or {}
    return {
        "organisasjonsnummer": d.get("organisasjonsnummer", ""),
        "navn": d.get("navn", ""),
        "organisasjonsform.kode": orgform.get("kode", ""),
        "organisasjonsform.beskrivelse": orgform.get("beskrivelse", ""),
        "naeringskode1.kode": naering.get("kode", ""),
        "naeringskode1.beskrivelse": naering.get("beskrivelse", ""),
        "naeringskode2.kode": naering2.get("kode", ""),
        "naeringskode2.beskrivelse": naering2.get("beskrivelse", ""),
        "naeringskode3.kode": naering3.get("kode", ""),
        "naeringskode3.beskrivelse": naering3.get("beskrivelse", ""),
        "hjelpeenhetskode.kode": hjelp.get("kode", ""),
        "hjelpeenhetskode.beskrivelse": hjelp.get("beskrivelse", ""),
        "harRegistrertAntallAnsatte": _bool(d.get("harRegistrertAntallAnsatte")),
        "antallAnsatte": d.get("antallAnsatte", "") if d.get("antallAnsatte") is not None else "",
        "hjemmeside": d.get("hjemmeside", ""),
        "postadresse.adresse": _addr_line(post),
        "postadresse.poststed": post.get("poststed", ""),
        "postadresse.postnummer": post.get("postnummer", ""),
        "postadresse.kommune": post.get("kommune", ""),
        "postadresse.kommunenummer": post.get("kommunenummer", ""),
        "postadresse.land": post.get("land", ""),
        "postadresse.landkode": post.get("landkode", ""),
        "forretningsadresse.adresse": _addr_line(forr),
        "forretningsadresse.poststed": forr.get("poststed", ""),
        "forretningsadresse.postnummer": forr.get("postnummer", ""),
        "forretningsadresse.kommune": forr.get("kommune", ""),
        "forretningsadresse.kommunenummer": forr.get("kommunenummer", ""),
        "forretningsadresse.land": forr.get("land", ""),
        "forretningsadresse.landkode": forr.get("landkode", ""),
        "institusjonellSektorkode.kode": sektor.get("kode", ""),
        "institusjonellSektorkode.beskrivelse": sektor.get("beskrivelse", ""),
        "sisteInnsendteAarsregnskap": d.get("sisteInnsendteAarsregnskap", ""),
        "registreringsdatoenhetsregisteret": d.get("registreringsdatoEnhetsregisteret", ""),
        "stiftelsesdato": d.get("stiftelsesdato", ""),
        "registrertIMvaRegisteret": _bool(d.get("registrertIMvaregisteret")),
        "frivilligMvaRegistrertBeskrivelser": "",
        "registrertIFrivillighetsregisteret": _bool(d.get("registrertIFrivillighetsregisteret")),
        "registrertIForetaksregisteret": _bool(d.get("registrertIForetaksregisteret")),
        "registrertIStiftelsesregisteret": _bool(d.get("registrertIStiftelsesregisteret")),
        "konkurs": _bool(d.get("konkurs")),
        "konkursdato": "",
        "underAvvikling": _bool(d.get("underAvvikling")),
        "underAvviklingDato": "",
        "underTvangsavviklingEllerTvangsopplosning": _bool(d.get("underTvangsavviklingEllerTvangsopplosning")),
        "tvangsopplostPgaManglendeDagligLederDato": "",
        "tvangsopplostPgaManglendeRevisorDato": "",
        "tvangsopplostPgaManglendeRegnskapDato": "",
        "tvangsopplostPgaMangelfulltStyreDato": "",
        "tvangsavvikletPgaManglendeSlettingDato": "",
        "overordnetEnhet": d.get("overordnetEnhet", ""),
        "maalform": d.get("maalform", ""),
        "vedtektsdato": "",
        "vedtektsfestetFormaal": "",
        "aktivitet": "",
    }


def parse_percentage(grunnlag):
    """'100%' -> '100', '88,0%' -> '88.0', '' -> ''."""
    if not grunnlag:
        return ""
    return grunnlag.strip().rstrip("%").strip().replace(",", ".")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    workspace = Path(__file__).resolve().parents[3]

    text = src.read_text(encoding="utf-8-sig")
    reader = csv.DictReader(io.StringIO(text), delimiter=";")

    members = {}       # orgnr -> row dict (dedup; a tree has unique members)
    edges = []         # (parent, child, percentage)
    for r in reader:
        child = (r.get("organisasjonsnummer") or "").strip()
        parent = (r.get("parentOrganisasjonsnummer") or "").strip()
        if not child:
            continue
        members[child] = r
        if parent:
            members.setdefault(parent, None)   # ensure parent is a member too
            edges.append((parent, child, parse_percentage(r.get("grunnlag"))))

    print(f"{len(members)} members, {len(edges)} konsern edges", file=sys.stderr)

    # Fetch each member's full enhet record.
    enhet_rows = []
    for orgnr in sorted(members):
        url = ENHET_API.format(orgnr)
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                d = json.load(resp)
            row = enhet_row(d)
            enhet_rows.append(row)
            print(f"  {orgnr}  {row['navn']:40.40}  land={row['forretningsadresse.landkode']}", file=sys.stderr)
        except Exception as e:
            print(f"  {orgnr}  FETCH FAILED: {e}", file=sys.stderr)
            sys.exit(1)
        time.sleep(0.2)

    enheter_path = workspace / "samples/norway/legal_unit/konsern-enheter.csv"
    with enheter_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=ENHETER_HEADER, lineterminator="\n")
        w.writeheader()
        for row in enhet_rows:
            w.writerow(row)
    print(f"wrote {enheter_path} ({len(enhet_rows)} rows)", file=sys.stderr)

    roller_path = workspace / "samples/norway/legal_relationship/konsern-roller.csv"
    with roller_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["influencing_tax_ident", "influenced_tax_ident", "rel_type_code", "percentage"])
        for parent, child, pct in edges:
            w.writerow([parent, child, REL_TYPE_CODE, pct])
    print(f"wrote {roller_path} ({len(edges)} rows)", file=sys.stderr)


if __name__ == "__main__":
    main()
