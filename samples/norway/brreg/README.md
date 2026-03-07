# BRREG (Bronnoysund Register Centre) Integration

Norway-specific data pipelines for importing from BRREG, the Norwegian business register.

## Relationship Types (Roller)

BRREG publishes role relationships ("roller") between legal units. These map to `legal_rel_type` entries with the `primary_influencer_only` flag controlling whether they form power group hierarchies.

See `seed-legal-rel-types.sql` for the seed data.

### Imported Roles

| Code | Name | `primary_influencer_only` | Forms PG? | Notes |
|------|------|--------------------------|-----------|-------|
| HFOR | Hovedforetak (parent company) | TRUE | Yes | Always 1:1 |
| EIKM | Eierkommune (owner municipality) | TRUE | Yes | Always 1:1 |
| KOMP | Komplementar (general partner) | TRUE | Yes | Always 1:1 |
| DTPR | Deltaker pro-rata | FALSE | No | Proportional liability partner, can be many-to-one |
| DTSO | Deltaker solidarisk | FALSE | No | Joint liability partner, can be many-to-one |

### Excluded Roles

- **KENK** (Kontrollerende enhet): Duplicates HFOR
- **KDEB** (Komplementar/debitor): Duplicates KOMP

### Why Not Percentages?

BRREG does not provide ownership percentages. Fabricating percentages (e.g., 50% for partners) caused exclusion constraint violations when multiple partners shared ownership. The type-based approach (`primary_influencer_only`) accurately reflects what BRREG provides: HFOR/EIKM/KOMP are structurally guaranteed to be single-root relationships.

### Partnership Structures (Future)

Norwegian partnership forms (ANS, DA, KS) have multiple co-equal partners via DTPR/DTSO relationships. These don't currently form power groups but could in the future via multi-root power group support. See `doc/power-groups.md` for the design direction.

## Pipeline Scripts

- `download-to-tmp.sh` — Downloads BRREG data files to `tmp/`
- `extract-roller-to-csv.py` — Extracts role relationships from BRREG JSON to CSV
- `brreg-import-downloads-from-tmp.sh` — Imports downloaded data into STATBUS
- `brreg-import-selection.sh` — Imports a selected subset
- `brreg-draw-samples.sh` / `.sql` — Draws random samples for testing

## Import Definitions

- `create-import-definition-hovedenhet-*.sql` — Legal unit (hovedenhet) import definitions
- `create-import-definition-underenhet-*.sql` — Establishment (underenhet) import definitions
- `create-import-definition-roller-2025.sql` — Role/relationship (roller) import definition
