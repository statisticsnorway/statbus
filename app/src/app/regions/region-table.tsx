"use client";
import React from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { Table, TableBody, TableHeader, TableRow, TableCell } from "@/components/ui/table";
import { usePermission } from "@/atoms/auth";
import { restClientAtom } from "@/atoms/rest-client";
import { RegionPlacer } from "@/components/map/region-placer";

/**
 * The regions: code, name and level, the columns every country needs (owner 2026-11-22, 5yxn4w).
 * `advanced` adds the optional centre: latitude, longitude and altitude. A region without a centre
 * shows "Not set", and an admin, who may change regions, gets "Place on map" there: an
 * OpenStreetMap search by the region's name to check on the map and save (owner 2026-11-23,
 * z2qt08).
 */
const RegionTable = ({
  regions,
  onChanged,
  advanced,
}: RegionTableProps & { onChanged?: () => void; advanced: boolean }) => {
  const { canAccessAdminTools } = usePermission();
  const client = useAtomValue(restClientAtom);
  // The installation's country narrows the place search to it.
  const { data: countryCode } = useSWR(client && canAccessAdminTools ? ["regions:country-code"] : null, async () => {
    const { data, error } = await client!.from("settings").select("country(iso_2)").limit(1).single();
    if (error) throw error;
    return (data.country as { iso_2: string } | null)?.iso_2 ?? null;
  });

  const saveCentre = async (id: number, point: { latitude: number; longitude: number }) => {
    const { error } = await client!
      .from("region")
      .update({ center_latitude: point.latitude, center_longitude: point.longitude })
      .eq("id", id);
    if (error) throw new Error(error.message);
    onChanged?.();
  };

  return (
    <Table className="font-sans">
      <TableHeader className="bg-gray-50">
        <TableRow>
          <TableCell>Code</TableCell>
          <TableCell>Name</TableCell>
          <TableCell className="text-right">Level</TableCell>
          {advanced ? (
            <>
              <TableCell className="text-right">Latitude</TableCell>
              <TableCell className="text-right">Longitude</TableCell>
              <TableCell className="text-right">Altitude</TableCell>
            </>
          ) : (
            <TableCell className="text-right">Centre</TableCell>
          )}
        </TableRow>
      </TableHeader>
      <TableBody>
        {regions.map(({ id, code, path, name, level, center_latitude, center_longitude, center_altitude }) => {
          const placed = center_latitude != null && center_longitude != null;
          return (
            <TableRow key={id} data-region-row={String(path)}>
              <TableCell className="py-3 lg:w-36">{code}</TableCell>
              <TableCell className="py-3 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-72 max-w-52">
                {name}
              </TableCell>
              <TableCell className="py-3 text-right tabular-nums">{level}</TableCell>
              {placed ? (
                advanced ? (
                  <>
                    <TableCell className="py-3 text-right tabular-nums">{center_latitude}</TableCell>
                    <TableCell className="py-3 text-right tabular-nums">{center_longitude}</TableCell>
                    <TableCell className="py-3 text-right tabular-nums">
                      {center_altitude ?? <span className="text-gray-500">Not set</span>}
                    </TableCell>
                  </>
                ) : (
                  <TableCell className="py-3 text-right">Set</TableCell>
                )
              ) : (
                <TableCell colSpan={advanced ? 3 : 1} className="py-2 text-right">
                  {canAccessAdminTools && client ? (
                    <RegionPlacer
                      region={{ name, path: String(path), latitude: null, longitude: null }}
                      countryCode={countryCode ?? null}
                      onSave={(point) => saveCentre(id, point)}
                    />
                  ) : (
                    <span className="text-gray-500">Not set</span>
                  )}
                </TableCell>
              )}
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
};
export default RegionTable;
