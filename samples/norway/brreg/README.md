# BRREG (Bronnoysund Register Centre) Integration

Norway-specific data pipelines for importing from BRREG, the Norwegian business register.

## Relationship Types (Roller)

BRREG publishes role relationships ("roller") between legal units. These map to `legal_rel_type` entries. **All imported role types form power groups** — any relationship edge, primary or not, contributes to clustering (see `doc/power-groups.md`, "Clustering and Hierarchy Algorithm"; proven by `test/sql/119_roller_data_power_groups.sql`, where an all-DTPR hierarchy forms its own power group). The `primary_influencer_only` flag controls cardinality (1:1 vs 1:N), the single-controller exclusion constraint, and hierarchy direction — not power-group membership.

See `seed-legal-rel-types.sql` for the seed data.

### Imported Roles

| Code | Name | `primary_influencer_only` | Notes |
|------|------|--------------------------|-------|
| HFOR | Hovedforetak (parent company) | TRUE | Always 1:1 |
| EIKM | Eierkommune (owner municipality) | TRUE | Always 1:1 |
| KOMP | Komplementar (general partner) | TRUE | Always 1:1 |
| DTPR | Deltaker pro-rata | FALSE | Proportional liability partner, can be many-to-one |
| DTSO | Deltaker solidarisk | FALSE | Joint liability partner, can be many-to-one |

### Excluded Roles

- **KENK** (Kontrollerende enhet): Duplicates HFOR
- **KDEB** (Komplementar/debitor): Duplicates KOMP

### Why Not Percentages?

BRREG does not provide ownership percentages. Fabricating percentages (e.g., 50% for partners) caused exclusion constraint violations when multiple partners shared ownership. The type-based approach (`primary_influencer_only`) accurately reflects what BRREG provides: HFOR/EIKM/KOMP are structurally guaranteed to be single-root relationships.

### Partnership Structures

Norwegian partnership forms (ANS, DA, KS) have multiple co-equal partners via DTPR/DTSO relationships. These DO form power groups today: the partners and the partnership cluster into one group, and a unit influenced by several partners is a multi-root case handled by `power_root` (`derived_root_status = 'multi'`). What DTPR/DTSO edges do NOT do is establish single-controller hierarchy — they are 1:N, outside the exclusion constraint, and carry no `primary` flag. How such non-controlling edges relate to the controlling (konsern) view is the subject of the power-group viewpoints design (STATBUS-179). See `doc/power-groups.md`.

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
