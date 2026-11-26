"use client";
import React, { useState } from "react";
import { Map as MapIcon, Pencil } from "lucide-react";
import { Table, TableBody, TableHeader, TableRow, TableCell } from "@/components/ui/table";
import { usePermission } from "@/atoms/auth";
import type { Tables } from "@/lib/database.types";
import { RegionCentreDialog } from "./region-centre-dialog";

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
  const [opened, setOpened] = useState<{ region: Tables<"region">; editing: boolean } | null>(null);

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
            const { id, code, path, name, level, latitude, longitude, altitude } = region;
            const placed = latitude != null && longitude != null;
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
                          {latitude}, {longitude},{" "}
                          {altitude ?? <span className="text-gray-400" title="Altitude not set">·</span>}
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
        <RegionCentreDialog
          region={opened.region}
          editing={opened.editing}
          onClose={() => setOpened(null)}
          onSaved={() => {
            setOpened(null);
            onChanged?.();
          }}
        />
      )}
    </>
  );
};
export default RegionTable;
