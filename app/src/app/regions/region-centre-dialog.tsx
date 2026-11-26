"use client";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { restClientAtom } from "@/atoms/rest-client";
import { LocationPicker, type PointValues } from "@/components/map/location-picker";

/** The centre of a region as stored in public.region. */
export interface RegionCentre {
  id: number;
  name: string;
  center_latitude: number | null;
  center_longitude: number | null;
  center_altitude: number | null;
}

/** A stored coordinate as the picker's text, empty when not set. */
const asText = (n: number | null) => (n == null ? "" : String(n));

/** The picker's text back to a stored value: empty is not set, anything else must be a number. */
function asNumber(text: string, label: string): number | null {
  if (text.trim() === "") return null;
  const n = Number(text);
  if (!Number.isFinite(n)) throw new Error(`${label} is not a number: ${text}`);
  return n;
}

/**
 * A region's centre in the location dialog, shown or edited (owner 2026-11-26, 5yxn4w): the
 * Regions list opens it from a row, the Regions map from the selected region, so a wrong centre
 * seen on the map is fixed where it is seen. Edit saves to public.region and calls `onSaved`.
 */
export function RegionCentreDialog({
  region,
  editing,
  onClose,
  onSaved,
}: {
  region: RegionCentre;
  editing: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const client = useAtomValue(restClientAtom);
  // The installation's country narrows OpenStreetMap's place search to it.
  const { data: countryCode } = useSWR(client ? ["regions:country-code"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(iso_2)").limit(1).single();
    if (error) throw error;
    return (data.country as { iso_2: string } | null)?.iso_2 ?? null;
  });

  const save = async (values: PointValues) => {
    const centre = {
      center_latitude: asNumber(values.latitude, "Latitude"),
      center_longitude: asNumber(values.longitude, "Longitude"),
      center_altitude: asNumber(values.altitude, "Altitude"),
    };
    const { error } = await client!.from("region").update(centre).eq("id", region.id);
    if (error) throw new Error(error.message);
    onSaved();
  };

  return (
    <LocationPicker
      open
      subject="region"
      editing={editing}
      values={{
        latitude: asText(region.center_latitude),
        longitude: asText(region.center_longitude),
        altitude: asText(region.center_altitude),
      }}
      regionCentre={null}
      address={() => ({ line: region.name, countryCode: countryCode ?? null, regionName: null })}
      onClose={onClose}
      onUse={save}
    />
  );
}
