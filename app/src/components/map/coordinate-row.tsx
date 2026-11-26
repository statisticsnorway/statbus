"use client";

import { useRef } from "react";
import type { Tables } from "@/lib/database.types";
import { LocationField } from "./location-field";
import type { AddressForLookup } from "./location-picker";

/**
 * The place of a physical location in its form (z2qt08): a map with the point, see LocationField.
 * It reads the address from the form it stands in when the large map opens, so an address typed
 * just before is the one looked up: the address parts, postcode and postplace as one line, the
 * country's ISO code (OpenStreetMap's matches stay in that country) and the region's name.
 */
export function CoordinateRow({
  isEditing,
  stored,
  regions,
  countries,
  regionId,
}: {
  isEditing: boolean;
  stored: { latitude: unknown; longitude: unknown; altitude: unknown };
  regions: Tables<"region">[];
  countries: Tables<"country">[];
  /** The location's region as the form shows it; the map centres there when there is no point. */
  regionId: unknown;
}) {
  const rowRef = useRef<HTMLDivElement>(null);
  const field = (name: string) =>
    rowRef.current
      ?.closest("form")
      ?.querySelector<HTMLInputElement>(`input[name="${name}"]`)
      ?.value.trim() ?? "";
  const regionOf = (id: unknown) =>
    regions.find((r) => String(r.id) === String(id ?? ""));
  const region = regionOf(regionId);
  const regionCentre = region
    ? { latitude: region.latitude, longitude: region.longitude }
    : null;

  const address = (): AddressForLookup => {
    const street = ["address_part1", "address_part2", "address_part3"]
      .map(field)
      .filter(Boolean);
    const post = [field("postcode"), field("postplace")]
      .filter(Boolean)
      .join(" ");
    const country = countries.find((c) => String(c.id) === field("country_id"));
    return {
      line: [...street, post].filter(Boolean).join(", "),
      countryCode: country?.iso_2?.toLowerCase() ?? null,
      regionName: regionOf(field("region_id") || regionId)?.name ?? null,
    };
  };

  return (
    <div ref={rowRef} data-coordinate-row="">
      <LocationField
        isEditing={isEditing}
        stored={stored}
        regionCentre={regionCentre}
        address={address}
      />
    </div>
  );
}
