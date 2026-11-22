# Units on a map: build plan (z2qt08)

Status: **draft for the owner's design session**. Nothing here is decided until
the owner answers the questions in section 7; each is also asked on the task
(`hug task show z2qt08`). Facts behind every claim, in the main checkout
(`/Users/jhf/ssb/statbus`): `tmp/hug/z2qt08-data/facts.md` (database, measured
on the Norway copy, queries `q1..q5.sql` beside it) and
`tmp/hug/z2qt08-app/facts.md` (app, with Erik's PR #325 diff).

## 1. What we are building

One map component in the app, opened from five places, each time showing the
units **the page already shows**: the same filters, the same time frame, the
signed-in session. Plus a picker on the location edit form that fills latitude
and longitude from a point instead of typing.

| # | Place | Shows | Data it needs |
|---|---|---|---|
| A | Unit links page (`/legal-units/[id]/links` and siblings) | this unit and its related units | `relevant_statistical_units(unit_type, unit_id, valid_on)` (already returns coordinates) |
| B | Search (`/search`, button beside Export) | the current search result | the search's own PostgREST params (`derivedApiSearchParamsAtom`), `select=` swapped |
| C | Reports (`/reports`) | counts per region, drill down | per-region counts (see section 4) |
| D | Regions (`/regions`) | each region at its centre | `region.center_latitude/longitude` (exists; 393 of 417 Norway regions have one) |
| E | Location edit form (Identification, physical location) | one draggable point | the address, a geocoder, the form's existing `updateLocation` action |

## 2. Where we stand (facts)

- **No coordinates in the data yet.** On the Norway copy 6 of 1.96M units have
  any. Coordinates exist in the schema end to end (`location.latitude/longitude`
  to `statistical_unit.physical_latitude/longitude`, the import's
  `physical_location` step, the CSV export). Until data is loaded, A, B and E
  show nothing useful; C and D work from region centres.
- **Erik's coordinate files (PR #326, task r39dqb) have two defects** found
  tonight:
  1. `legal_unit/statistical_units_legal_coords.csv` has exactly 1,048,575 data
     rows, Excel's sheet limit, and ends at "WORKS ON MY MACHINE AS"; the
     register has 1,134,475 current legal units, 8,612 of them sorting after that
     name (all of W-Z, Æ, Ø, Å). The file was cut by Excel.
  2. `establishment/statistical_units_estab_coords.csv`: 4,711 of 770,040 rows
     lack a longitude (rows of 2 or 3 fields: names with a comma or a line break
     broke the CSV), 10 fall outside Norway's box.
  Both are recorded on r39dqb; the fix is a fresh export from Erik's source,
  not hand repair.
- **No PostGIS**, no index on coordinates. Measured on 1.13M current legal units:
  count per region id 1.4 s (0.45 s with an activity filter); 5,000 points
  inside one county 0.22 s; a live 0.1° grid over everything 11.7 s
  (synthetic data). `statistical_history_facet` has the region path but no
  coordinates and is no faster than the live count (1.76 s).
- **The app has no map library**, no CSP (tiles and `blob:` workers load
  today), loads heavy libraries with `import()` already (Highcharts), and has
  no geocoding.
- PostgREST aggregates are enabled (`PGRST_DB_AGGREGATES_ENABLED`), so
  `select=physical_region_id,count()` with the search's filter works without
  a new RPC.

## 3. The map component (shared by all five)

- `maplibre-gl` (MapLibre GL JS, BSD; Erik's prototypes use it) as an npm
  dependency, loaded with `import()` only on map pages (about 220 KB gzip).
- `app/src/components/map/`:
  - `unit-map.tsx`: the map, client only. Props: a GeoJSON source of points
    or of region counts, the colour per unit type (the existing unit-type
    colours: enterprise pink, legal unit blue, establishment green), a click
    handler. Clustering from Erik's PR (#325: clusters, per-variable sums in
    `clusterProperties`, percentile colour stops) moves here.
  - `map-popup.tsx`: name linked to the unit page, type, activity, region,
    status, the statistical variables.
  - `basemap.ts`: one place that names the tile style URL and attribution
    (question 2).
  - Pure helpers with jest tests (node environment): rows to GeoJSON,
    percentile stops, cluster sums, the counts query builder.
- A truncation notice whenever the points shown are fewer than the matches
  ("5,000 of 31,204 shown, narrow the search"), and a plain "no unit has
  coordinates" message instead of an empty map (both from Erik's earlier
  prototypes).

## 4. Staying fast on a full register

Owner 2026-11-22: the places that show a known, small set of units (regions,
a unit's links, reports by region, the location picker) use the units and
regions **as they are**, with no change to the database. A map of **any search
result** cannot: it needs its own design, a table of units keyed by shortened
quad keys at several zoom levels, linked from the units, so a map of millions
of units reads counts per tile at the zoom shown. That design is the last
phase (section 6) and gets its own session; the points threshold (question 3)
and the grid (question 4) belong to it.

For the first phases:

- Regions and reports draw counts per region at the region centres:
  `select=physical_region_id,count()` on `statistical_unit` (1.4 s for all
  Norway legal units, 0.45 s with an activity filter; measured).
- A unit's links page draws its related units as points: a few hundred at
  most, from `relevant_statistical_units`.
- The location picker draws one point.

## 5. Each place in detail

- **B Search** (`SearchPageClient.tsx:117`, beside `ExportCSVLink`): a "Map"
  button to `/search/map?<same query string>`. The page reads the same Jotai
  search atoms, so filters and time frame carry over; back returns to the list.
  Its data comes from the quad-key table of section 4, designed in its own
  session.
- **A Links**: a "Map" section on the links page (`TopologySlot` neighbour),
  the unit highlighted, related units (`relevant_statistical_units`) around it,
  at most a few hundred points, so always points.
- **C Reports**: a "Map" tab beside the reports' charts: counts per level-1
  region, click for level 2 (the search map for a region follows once B
  exists). Colour by
  count or by a statistical variable sum (`stats_summary`).
- **D Regions**: lat/lon columns in the regions table (they exist in the data
  but are not shown) and a "Map" button: every region at its centre, label and
  count of units; regions without a centre listed beside the map (on Norway:
  the shelf, airspace, abroad, Svalbard reserves, "uoppgitt").
- **E Location form** (`general-info-form.tsx:216-231`): a "Pick on map"
  button opens a dialog (shadcn `Dialog`) with the map centred on the current
  point, else on the address found by the geocoder (question 5), else on the
  unit's region centre; drag the pin; OK fills latitude and longitude (and
  leaves altitude); Save works as today through `updateLocation`.

## 6. Order of work (proposal)

| Phase | Work | Needs |
|---|---|---|
| 0 | Coordinates for Norway: kvbebr (naming), dbmsxy (an import that updates only lat/lon on existing units; today a coordinates-only file fails), r39dqb (load, after a fresh export), 4pj9bz (2026 regions, the list Erik's region centres follow) | owner's decisions on those tasks |
| 1 | Map component + **D Regions** (works today from region centres) | question 2 |
| 2 | **A Links map**, **C Reports map** (units and regions as they are) | phase 1; links useful once phase 0 data is in |
| 3 | **E Location picker** with geocoding | question 5 |
| 4 | **B Search map** (5nq78t, Erik's Map beside Export): first its own design session for the quad-key table, then the build | owner's design; questions 3, 4 |

Owner 2026-11-22 (question 1): Regions first; the search map waits for its
own database design, the other places use the units as they are.

Each phase is its own STOP for the owner to see it before it is committed, as
for every feature. Browser checks are driven Firefox runs with screenshots in
`tmp/hug/`; the app has no Playwright suite (5nq78t's check 2 asks for one), so
adding one is its own decision.

## 7. Questions for the owner (each is a separate ask on z2qt08)

1. **First place**: answered 2026-11-22: Regions first; Search last, after
   its own design (a quad-key table at several zoom levels).
2. **Base map tiles**: (a) OpenFreeMap public tiles (no key, free, no SLA, the
   browser calls tiles.openfreemap.org; Erik's choice); (b) a self-hosted
   country extract as one PMTiles file served by our own Caddy (no third
   party at run time, works offline in a closed network, one file per country
   to keep current); (c) configurable per installation, defaulting to (a).
3. **Points threshold**: show points up to 5,000 matches and region counts
   above, or another number? Erik (5nq78t) proposes disabling the button
   above about 100,000 units with coordinates; MapLibre clusters 100,000
   points in the browser, but fetching them is about 20 times the 5,000-row
   fetch (0.22 s measured for 5,000 in one county), and region counts above
   the threshold keep the button useful for any selection.
4. **Finer than regions**: is drill-down by region enough for now, or do you
   want a precomputed grid (a cell column maintained by the derive pipeline)
   in the first build?
5. **Geocoding on the location form**: (a) Kartverket's open address API for
   Norway (`ws.geonorge.no/adresser/v1/sok`, interactive lookups only), with no
   lookup elsewhere; (b) OpenStreetMap's Nominatim for all countries (1 request
   per second, no bulk); (c) a geocoder chosen per installation in settings;
   (d) no geocoding, the dialog starts at the region centre and the user moves
   the pin.
6. **The map's page or a dialog**: search, reports and regions maps as their
   own full-width pages (`/search/map`, linkable, back button works), with a
   dialog only for the location picker, as proposed?
7. **Erik's PR #325**: close it with a comment pointing here once the app map
   replaces it, and credit his clustering and colour work in the commit?

## 8. Branch

`feat/units-on-map`, worktree `../statbus-map`, from master 2866d0b55. Nothing
committed beyond this plan until the owner has answered section 7.
