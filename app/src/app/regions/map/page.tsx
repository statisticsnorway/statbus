"use client";

import { useAtomValue } from "jotai";
import { restClientAtom } from "@/atoms/rest-client";
import type { RegionCountRow } from "@/components/map/map-data";
import { RegionsHeader } from "../regions-header";
import { RegionsMap, type RegionsMapSource } from "./regions-map";

/** The Regions map: every unit in the frame, by region (z2qt08). */
export default function RegionsMapPage() {
  const client = useAtomValue(restClientAtom);
  const source: RegionsMapSource = {
    key: "all",
    // One row per unit type, region path and country: PostgREST sums the facet's counts
    // (1,793 rows, 0.18 s on Norway, tmp/z2qt08-map-fetch2.sql).
    fetchRows: async (validOn) => {
      const { data, error } = await client!
        .from("statistical_unit_facet")
        .select(
          "unit_type,physical_region_path,physical_country_id,count.sum()"
        )
        .lte("valid_from", validOn)
        .gt("valid_until", validOn);
      if (error) throw error;
      // postgrest-js cannot type an aggregate select, so the rows are typed here.
      type Row = Omit<RegionCountRow, "count"> & { sum: number };
      return ((data ?? []) as unknown as Row[]).map(({ sum, ...r }) => ({
        ...r,
        count: sum,
      }));
    },
    searchFilter: new URLSearchParams(),
  };
  return (
    <RegionsMap
      basePath="/regions/map"
      source={source}
      header={(trail) => <RegionsHeader view="map" breadcrumb={trail} />}
    />
  );
}
