import { countsByRegion, depthForZoom, featureBounds, framingFeatures, maxRegionDepth, maxTotal, pathPrefix, regionFeatures, unitTypeColourVariable, unplacedCount, type RegionCountRow } from "./map-data";

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
  { path: "03", name: "Oslo", center_latitude: 59.94, center_longitude: 10.77 },
  { path: "46", name: "Vestland", center_latitude: 60.9, center_longitude: 6.0 },
  { path: "25", name: "Utlandet", center_latitude: null, center_longitude: null },
  { path: "46.4601", name: "Bergen", center_latitude: 60.39, center_longitude: 5.32 },
  { path: "46.4602", name: "Kinn", center_latitude: 61.6, center_longitude: 5.0 },
];

describe("pathPrefix", () => {
  it("keeps the first labels, and a shorter path as it is", () => {
    expect([pathPrefix("46.4601", 1), pathPrefix("46.4601", 2), pathPrefix("46", 2)]).toEqual(["46", "46.4601", "46"]);
  });
});

describe("countsByRegion", () => {
  it("sums each unit type per county, leaving out power groups and units without a region", () => {
    expect(countsByRegion(rows, 1)).toEqual([
      { path: "03", counts: { enterprise: 0, legal_unit: 20, establishment: 0 } },
      { path: "25", counts: { enterprise: 0, legal_unit: 3, establishment: 0 } },
      { path: "46", counts: { enterprise: 2, legal_unit: 15, establishment: 7 } },
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

describe("unitTypeColourVariable", () => {
  it("names the app's unit-type colour variables from globals.css", () => {
    expect([unitTypeColourVariable("legal_unit"), unitTypeColourVariable("establishment", 700)]).toEqual([
      "--color-legal_unit-500",
      "--color-establishment-700",
    ]);
  });
});
