"use client";
import React from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { Table, TableBody, TableHeader, TableRow, TableCell } from "@/components/ui/table";
import { usePermission } from "@/atoms/auth";
import { restClientAtom } from "@/atoms/rest-client";
import { RegionPlacer } from "@/components/map/region-placer";

/**
 * The regions with their centre. A region without one shows "Not set", and an admin, who may
 * change regions, gets "Place on map" there: an OpenStreetMap search by the region's name to
 * check on the map and save (owner 2026-11-23, z2qt08).
 */
const RegionTable = ({ regions, onChanged }: RegionTableProps & { onChanged?: () => void }) => {
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
          <TableCell>Path</TableCell>
          <TableCell>Name</TableCell>
          <TableCell className="text-right">Latitude</TableCell>
          <TableCell className="text-right">Longitude</TableCell>
        </TableRow>
      </TableHeader>
      <TableBody>
        {regions.map(({ id, code, path, name, center_latitude, center_longitude }) => (
          <TableRow key={id} data-region-row={String(path)}>
            <TableCell className="py-3 lg:w-36">{code}</TableCell>
            <TableCell className="py-3 lg:w-36">{String(path)}</TableCell>
            <TableCell className="py-3 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-72 max-w-52">
              {name}
            </TableCell>
            {center_latitude != null && center_longitude != null ? (
              <>
                <TableCell className="py-3 text-right tabular-nums">{center_latitude}</TableCell>
                <TableCell className="py-3 text-right tabular-nums">{center_longitude}</TableCell>
              </>
            ) : (
              <TableCell colSpan={2} className="py-2 text-right">
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
        ))}
      </TableBody>
    </Table>
  );
};
export default RegionTable;
