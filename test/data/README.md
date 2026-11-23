# Test data

Files here are inputs for the SQL tests in `test/sql/`. The number in a file
name is the test that reads it.

Everything here is invented, generated or public. Files generated from a
partner's data are listed below with their provenance and the script that
generated them; no file here holds a firm's or person's identifying data
that is not public.

## Provenance

### 318_albania_legal_units.csv and 318_albania_establishments.csv

Read by test 404 (`test/sql/404_regression_albania_import.sql`), which
reproduces an import analysis hang with an Albania-shaped register:
333 legal unit rows (300 units) and 8,439 establishment rows.

**Source.** An extract from Albania's business register, received from the
Albanian partner for testing. It was partially anonymised when received:
names were cut to four letters, tax identifiers shortened to seven
characters (not the ten-character NUIS), street addresses and post codes
replaced with placeholders, and birth dates set to 1 January of invented
years (up to 2315). Websites, e-mail addresses, phone numbers and figures
were left as in the register, so the firms could still be identified.

**History.** From 2026-01-29 (`cc13d63dd`) to 2026-11-23, the repository
held that extract. It was already partially anonymised as described above,
but the anonymisation was not documented anywhere, so a reader could not
tell it from raw register data. On 2026-11-23 a security review found the
columns that still identified firms; `cfb49e73a` and the following commit
replaced them with generated values and added this record.

**Decision (2026-11-23, Erik Søberg and Jørgen H. Fjeld, SSB).** The
regenerated data is sufficiently anonymised, and git history is not
rewritten: earlier commits keep the partially anonymised extract described
above. Recorded in task b5xp5f.

**Generation.** `318_albania_generate.py` produced the current files from
that extract and documents every column:

| Columns | Treatment |
|---|---|
| tax_ident, name, address lines, post places, phone, landline, mobile, fax | generated value of the same shape; one source value always gives the same generated value |
| legal_unit_tax_ident (establishments) | same mapping as tax_ident, so each establishment still points to its legal unit |
| email_address, web_address | numbered placeholders on example.org |
| employees, turnover, male, female, selfemp, punpag | generated numbers of the same digit count |
| activity codes, region, legal form, sector | the whole set moves from one unit to another unit with the same empty cells; the file holds the same codes in the same proportions, but no longer tied to the unit that had them |
| dates, country codes, coordinates, status, size, data source | kept: already synthetic or not identifying, and test 404 depends on them |

Rows the test asserts on keep their codes (foreign units with a region, the
row with an out-of-range latitude, rows without an identifier), so the test
produces the same row states, actions and errors as with the source files.

The source extract is not kept in the repository.

### 341_duplicate_tax_ident_big_file.csv

Read by test 341, which checks that an import refuses the rows sharing a tax
identifier and imports the rest: 600 rows, three of them (1, 232, 600)
sharing the deliberate tax identifier `01`.

**Source.** A list of 600 Moroccan company and person names with a
statistical and a tax identifier each (no addresses, contacts or figures),
committed on 2026-01-21 (`003384b83`). It was meant to be anonymised test
data, but the names were real-looking register names and this was not
documented.

**Decision and replacement (2026-11-23).** Replaced in the same review as
the Albania files, under the same decision (sufficiently anonymised, git
history not rewritten; task b5xp5f). `341_duplicate_ident_generate.py`
produced the current file and documents every column: names become
`Unit NNN`; statistical and tax identifiers become generated numbers of the
same digit count, one source value always giving the same number, so every
duplicate and every empty cell stays where it was; values of up to two
digits (such as `01`) are kept. Test 341 gives the same result as before:
597 units imported, the same three rows refused.

### Other files

`318_albania_legal_forms.csv`, `318_albania_regions.csv` and
`318_albania_sectors.csv` are classification lists (public reference data).

The Norwegian files (`*norwegian*.csv`) are built from, or shaped like, the
Norwegian Central Coordinating Register for Legal Entities (BRREG), which is
public open data; the full BRREG loaders live in `samples/norway/brreg/`.

The remaining files, including `340_duplicate_tax_ident_small_file.csv`,
were written for their tests from the invented demo units (for example
`NILE PEARL WATER`, `Nordic Holdings ASA`, `Unit A Partition Test`).
