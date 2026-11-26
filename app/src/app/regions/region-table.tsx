"use client";
import React, { useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { Map as MapIcon, Pencil } from "lucide-react";
import { Table, TableBody, TableHeader, TableRow, TableCell } from "@/components/ui/table";
import { usePermission } from "@/atoms/auth";
import { restClientAtom } from "@/atoms/rest-client";
import { LocationPicker, type PointValues } from "@/components/map/location-picker";
import type { Tables } from "@/lib/database.types";

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
 * The regions: code, name and level, the columns every country needs. With `showCoordinates` on,
 * one Coordinates column sums up the region's centre (latitude, longitude, and the altitude when set)
 * and offers Show, and Edit for those who may change regions (owner 2026-11-26, 5yxn4w). Both open
 * the location dialog the unit's form uses; Edit saves the centre to public.region.
 */
const RegionTable = ({
  regions,
  onChanged,
  showCoordinates,
}: RegionTableProps & { onChanged?: () => void; showCoordinates: boolean }) => {
  const { canAccessAdminTools } = usePermission();
  const client = useAtomValue(restClientAtom);
  const [opened, setOpened] = useState<{ region: Tables<"region">; editing: boolean } | null>(null);
  // The installation's country narrows OpenStreetMap's place search to it.
  const { data: countryCode } = useSWR(client && showCoordinates ? ["regions:country-code"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(iso_2)").limit(1).single();
    if (error) throw error;
    return (data.country as { iso_2: string } | null)?.iso_2 ?? null;
  });

  const saveCentre = async (id: number, values: PointValues) => {
    const centre = {
      center_latitude: asNumber(values.latitude, "Latitude"),
      center_longitude: asNumber(values.longitude, "Longitude"),
      center_altitude: asNumber(values.altitude, "Altitude"),
    };
    const { error } = await client!.from("region").update(centre).eq("id", id);
    if (error) throw new Error(error.message);
    setOpened(null);
    onChanged?.();
  };

  return (
    <>
      <Table className="font-sans">
        <TableHeader className="bg-gray-50">
          <TableRow>
            <TableCell>Code</TableCell>
            <TableCell>Name</TableCell>
            <TableCell className="text-right">Level</TableCell>
            {showCoordinates && (
              <TableCell className="text-right">
                Coordinates <span className="text-xs font-normal text-gray-500">(lat, lon, alt)</span>
              </TableCell>
            )}
          </TableRow>
        </TableHeader>
        <TableBody>
          {regions.map((region) => {
            const { id, code, path, name, level, center_latitude, center_longitude, center_altitude } = region;
            const placed = center_latitude != null && center_longitude != null;
            return (
              <TableRow key={id} data-region-row={String(path)}>
                <TableCell className="py-3 lg:w-36">{code}</TableCell>
                <TableCell className="py-3 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-72 max-w-52">
                  {name}
                </TableCell>
                <TableCell className="py-3 text-right tabular-nums">{level}</TableCell>
                {showCoordinates && (
                  <TableCell className="py-1.5 text-right" data-region-coordinates="">
                    <span className="inline-flex items-center gap-1">
                      {placed ? (
                        // All three always, in the header's order; a missing altitude is a grey dot,
                        // so its place shows without words (owner 2026-11-26).
                        <span className="tabular-nums">
                          {center_latitude}, {center_longitude},{" "}
                          {center_altitude ?? <span className="text-gray-400" title="Altitude not set">·</span>}
                        </span>
                      ) : (
                        <span className="text-gray-500">Not set</span>
                      )}
                      <button
                        type="button"
                        className="ml-1 rounded p-1.5 text-gray-600 hover:bg-gray-100 hover:text-gray-900 disabled:opacity-30 disabled:hover:bg-transparent"
                        onClick={() => setOpened({ region, editing: false })}
                        disabled={!placed}
                        title={placed ? "Show on the map" : "No centre to show"}
                        aria-label={`Show ${name} on the map`}
                        data-region-show=""
                      >
                        <MapIcon className="h-4 w-4" />
                      </button>
                      {canAccessAdminTools && (
                        <button
                          type="button"
                          className="rounded p-1.5 text-gray-600 hover:bg-gray-100 hover:text-gray-900"
                          onClick={() => setOpened({ region, editing: true })}
                          title="Edit the centre"
                          aria-label={`Edit the centre of ${name}`}
                          data-region-edit=""
                        >
                          <Pencil className="h-4 w-4" />
                        </button>
                      )}
                    </span>
                  </TableCell>
                )}
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
      {opened && (
        <LocationPicker
          open
          subject="region"
          editing={opened.editing}
          values={{
            latitude: asText(opened.region.center_latitude),
            longitude: asText(opened.region.center_longitude),
            altitude: asText(opened.region.center_altitude),
          }}
          regionCentre={null}
          address={() => ({ line: opened.region.name, countryCode: countryCode ?? null, regionName: null })}
          onClose={() => setOpened(null)}
          onUse={(values) => saveCentre(opened.region.id, values)}
        />
      )}
    </>
  );
};
export default RegionTable;
