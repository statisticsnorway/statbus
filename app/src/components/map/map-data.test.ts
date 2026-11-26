import { childCounts, countryCounts, countsAll, countsByRegion, countsUnder, selectedCountryCode, selectionDepth, selectionParent, selectionTrail, worldCounts, depthForZoom, featureBounds, framingFeatures, linksUnitPoints, maxRegionDepth, maxTotal, pathPrefix, pickerStart, locationView, facetParams, liveCountSelect, resolveQualityForCount, roundCoordinate, regionFeatures, unitTypeColourVariable, unplacedCount, spiderNodes, type RegionCountRow } from "./map-data";

// z2qt08: the Regions map counts units per region path prefix from statistical_unit_facet and
// draws each region with a centre; regions without one are listed beside the map.
const rows: RegionCountRow[] = [
  { unit_type: "legal_unit", physical_region_path: "46.4601", count: 10 },
  { unit_type: "legal_unit", physical_region_path: "46.4602", count: 5 },
  { unit_type: "establishment", physical_region_path: "46.4601", count: 7 },
  { unit_type: "enterprise", physical_region_path: "46", count: 2 },
  { unit_type: "legal_unit", physical_region_path: "03.0301", count: 20 },
  { unit_type: "legal_unit", physical_region_path: "25.11", count: 3 },
  { unit_type: "legal_unit", physical_region_path: null, count: 4 },
  { unit_type: "power_group", physical_region_path: "03.0301", count: 9 },
];
const regions = [
  { id: 1, path: "03", name: "Oslo", latitude: 59.94, longitude: 10.77, altitude: null },
  { id: 2, path: "46", name: "Vestland", latitude: 60.9, longitude: 6.0, altitude: null },
  { id: 3, path: "25", name: "Utlandet", latitude: null, longitude: null, altitude: null },
  { id: 4, path: "46.4601", name: "Bergen", latitude: 60.39, longitude: 5.32, altitude: 12 },
  { id: 5, path: "46.4602", name: "Kinn", latitude: 61.6, longitude: 5.0, altitude: null },
];

describe("pathPrefix", () => {
  it("keeps the first labels, and a shorter path as it is", () => {
    expect([pathPrefix("46.4601", 1), pathPrefix("46.4601", 2), pathPrefix("46", 2)]).toEqual(["46", "46.4601", "46"]);
  });
});

describe("countsByRegion", () => {
  it("sums each unit type per county, power groups too, leaving out units without a region", () => {
    expect(countsByRegion(rows, 1)).toEqual([
      { path: "03", counts: { enterprise: 0, legal_unit: 20, establishment: 0, power_group: 9 } },
      { path: "25", counts: { enterprise: 0, legal_unit: 3, establishment: 0, power_group: 0 } },
      { path: "46", counts: { enterprise: 2, legal_unit: 15, establishment: 7, power_group: 0 } },
    ]);
  });

  it("at municipality depth, a unit placed on the county stays at the county", () => {
    expect(countsByRegion(rows, 2).map((r) => [r.path, r.counts.legal_unit + r.counts.establishment + r.counts.enterprise])).toEqual([
      ["03.0301", 20],
      ["25.11", 3],
      ["46", 2],
      ["46.4601", 17],
      ["46.4602", 5],
    ]);
  });
});

describe("depthForZoom", () => {
  it("shows counties at country zoom and one level deeper per zoom band, down to the tree's depth", () => {
    // Morocco: regions 5 deep.
    expect([4, 6, 7.4, 7.5, 9, 10.5, 14].map((z) => depthForZoom(z, 5))).toEqual([1, 2, 2, 3, 4, 5, 5]);
    // Norway: 2 deep, so municipalities from zoom 6 on.
    expect([4, 6, 12].map((z) => depthForZoom(z, 2))).toEqual([1, 2, 2]);
  });

  it("reads the tree's depth from the region paths", () => {
    expect(maxRegionDepth([{ path: "01" }, { path: "01.051.01.01.1" }, { path: "02.1" }])).toBe(5);
  });
});

describe("unplacedCount", () => {
  it("counts the picked types without a region", () => {
    expect([unplacedCount(rows, ["legal_unit"]), unplacedCount(rows, ["enterprise"])]).toEqual([4, 0]);
  });
});

describe("regionFeatures", () => {
  it("places counties with a centre at it, totals the picked types, and lists the rest", () => {
    const { features, withoutCentre } = regionFeatures(regions, countsByRegion(rows, 1), ["legal_unit", "establishment"]);
    expect(features.features.map((f) => [f.properties.name, f.properties.total, f.geometry.coordinates])).toEqual([
      ["Oslo", 20, [10.77, 59.94]],
      ["Vestland", 22, [6.0, 60.9]],
    ]);
    expect(withoutCentre).toEqual([{ path: "25", name: "Utlandet", total: 3 }]);
  });

  it("leaves out a region with none of the picked types", () => {
    const { features } = regionFeatures(regions, countsByRegion(rows, 1), ["enterprise"]);
    expect(features.features.map((f) => f.properties.name)).toEqual(["Vestland"]);
  });
});

describe("featureBounds", () => {
  it("is the box around every point, or null for none", () => {
    const { features } = regionFeatures(regions, countsByRegion(rows, 1), ["legal_unit"]);
    expect([featureBounds(features.features), featureBounds([])]).toEqual([[6.0, 59.94, 10.77, 60.9], null]);
  });
});

describe("framingFeatures and maxTotal", () => {
  const point = (total: number, lon: number) =>
    ({ type: "Feature", geometry: { type: "Point", coordinates: [lon, 60] }, properties: { total } }) as GeoJSON.Feature<GeoJSON.Point, { total: number }>;
  it("frames the regions with at least 1% of the largest one, leaving out far-off small ones", () => {
    const features = [point(188463, 10.7), point(15070, 25), point(643, 16)];
    expect([framingFeatures(features).map((f) => f.properties.total), maxTotal(features), maxTotal([])]).toEqual([[188463, 15070], 188463, 0]);
  });
});

describe("linksUnitPoints", () => {
  const gjerdrum = { name: "Gjerdrum", path: "32.30", latitude: 60.08, longitude: 11.05 };
  const at = (lat: number | null, lon: number | null, type = "physical", region: typeof gjerdrum | null = null) => [
    { type, latitude: lat, longitude: lon, region },
  ];
  const hierarchy = {
    enterprise: {
      id: 10,
      legal_unit: [
        {
          id: 20,
          name: "VERIDIT AS",
          location: at(59.91, 10.75),
          establishment: [
            { id: 30, name: "Oslo office", location: at(59.92, 10.76) },
            { id: 31, name: "Gjerdrum shop", location: at(null, null, "physical", gjerdrum) },
            { id: 32, name: "Nowhere office", location: at(null, null) },
          ],
        },
        { id: 21, name: "Postal only AS", location: at(60.1, 10.2, "postal") },
      ],
      establishment: [{ id: 40, name: "Kiosk", location: at(60.39, 5.32) }],
    },
  };

  it("places units at their coordinates, else at their region's centre, marks the page's unit, and counts all", () => {
    const { features, total, atPoint, atRegion } = linksUnitPoints(hierarchy, { unitType: "establishment", id: 30 });
    expect(
      features.features.map((f) => [f.properties.unit_type, f.properties.name, f.properties.placed, f.properties.current, f.geometry.coordinates])
    ).toEqual([
      ["legal_unit", "VERIDIT AS", "point", false, [10.75, 59.91]],
      ["establishment", "Oslo office", "point", true, [10.76, 59.92]],
      ["establishment", "Gjerdrum shop", "region", false, [11.05, 60.08]],
      ["establishment", "Kiosk", "point", false, [5.32, 60.39]],
    ]);
    // Six units: three at their point, one at its region, the Nowhere office has neither, and
    // Postal only AS has only a postal location.
    expect([total, atPoint, atRegion]).toEqual([6, 3, 1]);
  });
});

describe("facetParams and liveCountSelect (5nq78t)", () => {
  const frame = "existence_from=lte.2026-11-24&existence_until=gt.2026-11-24";
  it("rewrites a facet-only search for statistical_unit_facet", () => {
    const api = new URLSearchParams(`unit_type=in.(legal_unit)&primary_activity_category_path=cd.C&domestic=is.true&${frame}`);
    expect(facetParams(api, 161)?.toString()).toBe(
      "unit_type=in.%28legal_unit%29&primary_activity_category_path=cd.C&physical_country_id=eq.161&valid_from=lte.2026-11-24&valid_until=gt.2026-11-24"
    );
    expect(facetParams(new URLSearchParams("domestic=is.false"), 161)?.toString()).toBe("physical_country_id=neq.161");
  });
  it("leaves to statistical_unit what the facet has no column for", () => {
    expect([
      facetParams(new URLSearchParams(`search=fts(simple).bygg:*&${frame}`), 161),
      facetParams(new URLSearchParams("select=*,quality_missing_region!inner()"), 161),
      facetParams(new URLSearchParams("unit_size_code=in.(small)"), 161),
      facetParams(new URLSearchParams("domestic=is.true"), null),
    ]).toEqual([null, null, null, null]);
  });
  it("turns status and legal form codes into the facet's ids, or leaves them live when a code is unknown", () => {
    const codeIds = { status: new Map([["active", 1], ["passive", 2]]), legalForm: new Map([["AS", 52]]) };
    expect([
      facetParams(new URLSearchParams("status_code=in.(active,passive)&legal_form_code=in.(AS)"), 161, codeIds)?.toString(),
      facetParams(new URLSearchParams("status_code=in.(gone)"), 161, codeIds),
    ]).toEqual(["status_id=in.%281%2C2%29&legal_form_id=in.%2852%29", null]);
  });
  it("counts live by region, keeping a filter's embedding", () => {
    // An empty embed cannot stand beside an aggregate in PostgREST (400: column does not exist), so
    // the count names one column inside it; the inner join still filters the units.
    expect([liveCountSelect(new URLSearchParams("search=x")), liveCountSelect(new URLSearchParams("select=*,quality_x!inner()"))]).toEqual([
      "unit_type,physical_region_path,physical_country_id,count()",
      "unit_type,physical_region_path,physical_country_id,count(),quality_x!inner(unit_type)",
    ]);
  });
  it("counts a quality check by joining its findings, with the variable's id for a per-variable rule", () => {
    const statIds = new Map([["employees", 7]]);
    const plain = resolveQualityForCount(new URLSearchParams("quality_check=missing_physical_location&unit_type=in.(enterprise)"), statIds);
    const perStat = resolveQualityForCount(new URLSearchParams("quality_check=establishments_above_legal_unit:employees"), statIds);
    expect([
      plain.get("quality_check"),
      liveCountSelect(plain),
      plain.get("quality_finding.rule"),
      plain.get("quality_finding.stat_definition_id"),
      plain.get("unit_type"),
      perStat.get("quality_finding.stat_definition_id"),
    ]).toEqual([
      null,
      "unit_type,physical_region_path,physical_country_id,count(),quality_finding!inner(unit_type)",
      "eq.missing_physical_location",
      "is.null",
      "in.(enterprise)",
      "eq.7",
    ]);
    expect(() => resolveQualityForCount(new URLSearchParams("quality_check=x:nope"), statIds)).toThrow("No statistical variable nope");
  });
});

describe("pickerStart and roundCoordinate", () => {
  const bergen = { latitude: 60.39, longitude: 5.32 };
  it("opens at the stored point, else the region's centre, else the whole map", () => {
    expect([
      pickerStart("59.943901", "10.772135", bergen),
      pickerStart("", "", bergen),
      pickerStart("95", "10", null),
      pickerStart(null, null, { latitude: null, longitude: null }),
    ]).toEqual([
      { center: [10.772135, 59.943901], zoom: 14, fromLocation: true },
      { center: [5.32, 60.39], zoom: 9, fromLocation: false },
      { center: [10, 62], zoom: 4, fromLocation: false },
      { center: [10, 62], zoom: 4, fromLocation: false },
    ]);
  });

  it("shows the point with its region's centre, the point alone, or the region alone", () => {
    const gjerdrum = { latitude: 60.08, longitude: 11.03 };
    expect([locationView("58", "9", gjerdrum), locationView("60.07", "11.04", null), locationView("", "", gjerdrum)]).toEqual([
      { center: [9, 58], zoom: 13, bounds: [9, 58, 11.03, 60.08], point: [9, 58], region: [11.03, 60.08] },
      { center: [11.04, 60.07], zoom: 13, bounds: null, point: [11.04, 60.07], region: null },
      { center: [11.03, 60.08], zoom: 9, bounds: null, point: null, region: [11.03, 60.08] },
    ]);
  });

  it("rounds to the six decimals location stores", () => {
    expect([roundCoordinate(10.7721354999), roundCoordinate(-0.00000049)]).toEqual([10.772135, -0]);
  });
});

describe("unitTypeColourVariable", () => {
  it("names the app's unit-type colour variables from globals.css", () => {
    expect([unitTypeColourVariable("legal_unit"), unitTypeColourVariable("establishment", 700)]).toEqual([
      "--color-legal_unit-500",
      "--color-establishment-700",
    ]);
  });
});

// z2qt08, owner 2026-11-23: the Regions map is a drill-down from the world through the
// installation's own country (id 1 here) to its regions; one selection decides what it shows.
describe("the map selection", () => {
  const NO = 1;
  const SE = 2;
  const worldRows: RegionCountRow[] = [
    { unit_type: "legal_unit", physical_region_path: "46.4601", physical_country_id: NO, count: 10 },
    { unit_type: "legal_unit", physical_region_path: "46.4602", physical_country_id: NO, count: 5 },
    { unit_type: "legal_unit", physical_region_path: "46", physical_country_id: NO, count: 2 },
    { unit_type: "legal_unit", physical_region_path: "03.0301", physical_country_id: NO, count: 20 },
    { unit_type: "legal_unit", physical_region_path: "460", physical_country_id: NO, count: 1 },
    { unit_type: "legal_unit", physical_region_path: null, physical_country_id: NO, count: 1 },
    { unit_type: "legal_unit", physical_region_path: null, physical_country_id: SE, count: 30 },
    { unit_type: "establishment", physical_region_path: null, physical_country_id: SE, count: 4 },
    { unit_type: "legal_unit", physical_region_path: null, physical_country_id: null, count: 7 },
  ];

  it("walks from the world through the country to a region and back", () => {
    expect(selectionTrail("46.4601")).toEqual([null, "", "46", "46.4601"]);
    expect(selectionTrail("")).toEqual([null, ""]);
    expect(selectionTrail(null)).toEqual([null]);
    expect([selectionParent("46.4601"), selectionParent("46"), selectionParent(""), selectionParent(null)]).toEqual(["46", "", null, null]);
    expect([selectionDepth(null), selectionDepth(""), selectionDepth("46"), selectionDepth("46.4601")]).toEqual([-1, 0, 1, 2]);
  });

  it("selects a foreign country by its code, one step below the world", () => {
    expect([selectedCountryCode("country:SE"), selectedCountryCode(""), selectedCountryCode("46"), selectedCountryCode(null)]).toEqual(["SE", null, null, null]);
    expect([selectionTrail("country:SE"), selectionParent("country:SE"), selectionDepth("country:SE")]).toEqual([[null, "country:SE"], null, 0]);
  });

  it("counts each unit type per country, leaving out units without a location", () => {
    const counts = countryCounts(worldRows);
    expect([counts.get(NO), counts.get(SE), counts.size]).toEqual([
      { enterprise: 0, legal_unit: 39, establishment: 0, power_group: 0 },
      { enterprise: 0, legal_unit: 30, establishment: 4, power_group: 0 },
      2,
    ]);
  });

  it("shows the country's counties, then a county's municipalities, with a county's own units at the county", () => {
    const counts = (s: string) => childCounts(worldRows, s, NO).map((c) => [c.path, c.counts.legal_unit]);
    expect(counts("")).toEqual([["03", 20], ["46", 17], ["460", 1]]);
    expect(counts("46")).toEqual([["46", 2], ["46.4601", 10], ["46.4602", 5]]);
  });

  it("counts a selection's region and everything below it, by path label, not by text prefix", () => {
    expect(countsUnder(worldRows, "46", NO).legal_unit).toBe(17);
    expect(countsUnder(worldRows, "", NO).legal_unit).toBe(39);
  });

  it("splits the world into the country, its units without a region, abroad by country and no location", () => {
    expect(worldCounts(worldRows, NO, ["legal_unit"])).toEqual({
      domestic: 39,
      domesticWithoutRegion: 1,
      abroad: [{ countryId: SE, count: 30 }],
      noLocation: 7,
    });
    expect(worldCounts(worldRows, NO, ["establishment"]).abroad).toEqual([{ countryId: SE, count: 4 }]);
  });

  it("counts each unit type in the whole world, home, abroad and without a location, for the legend at World", () => {
    expect(countsAll(worldRows)).toEqual({ enterprise: 0, legal_unit: 76, establishment: 4, power_group: 0 });
  });
});

describe("spiderNodes", () => {
  // A stack at Oslo's centre as on Vinmonopolet's map: units placed at their region, which no zoom splits.
  const unit = (unit_type: "legal_unit" | "establishment", id: number, placed: "point" | "region" = "region") => ({
    unit_type,
    id,
    name: `${unit_type === "legal_unit" ? "Vinmonopolet" : "Butikk"} ${id}`,
    href: `/${unit_type}/${id}`,
    current: false,
    placed,
    region_name: "Oslo",
  });

  it("gives a large stack one node per unit type and placement, with every unit in one node", () => {
    const stack = [unit("legal_unit", 1), ...Array.from({ length: 33 }, (_, i) => unit("establishment", 100 + i)), unit("establishment", 200, "point"), unit("establishment", 201, "point")];
    const nodes = spiderNodes(stack);
    expect(nodes.map((n) => [n.key, n.units.length, n.x, n.y])).toEqual([
      ["legal_unit:region", 1, 0, -56],
      ["establishment:point", 2, 48, 28],
      ["establishment:region", 33, -48, 28],
    ]);
  });

  it("gives a small stack one node per unit, so each can be picked", () => {
    const nodes = spiderNodes([unit("establishment", 7), unit("legal_unit", 3)]);
    expect(nodes.map((n) => [n.key, n.units.map((u) => u.id), n.x, n.y])).toEqual([
      ["legal_unit:3", [3], 0, -56],
      ["establishment:7", [7], 0, 56],
    ]);
  });
});
