"use client";

import React, { Suspense, useCallback, useState } from "react";
import { useAtom, useAtomValue } from "jotai";
import useSWR from "swr";
import { numberOfRegionsAtomAsync } from "@/atoms/getting-started";
import { restClientAtom } from "@/atoms/rest-client";
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm, type UploadPreview } from "@/app/getting-started/upload-csv-form";
import { ExampleDownloads } from "@/app/getting-started/example-downloads";
import { parseCsvRecords } from "@/app/getting-started/upload-csv-check";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { fetchWithAuth, getBrowserRestClient } from "@/context/RestClientStore";
import { previewRegionUpload, type RegionChange, type StoredRegion } from "./region-upload-preview";

/** The regions stored now, as the upload view reads and writes them. */
async function fetchStoredRegions(): Promise<StoredRegion[]> {
  const client = await getBrowserRestClient();
  const response = await fetchWithAuth(`${client.url}/region_upload`, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`Reading the regions failed (${response.status})`);
  return (await response.json()) as StoredRegion[];
}

/** One group of the check's summary: its count, and its first rows by name. */
function ChangeList({ title, rows, show }: { title: string; rows: RegionChange[]; show: (r: RegionChange) => string }) {
  if (rows.length === 0) return null;
  const shown = rows.slice(0, 5);
  return (
    <li>
      <span className="font-medium tabular-nums">{rows.length.toLocaleString()}</span> {title}
      <span className="text-gray-600">
        {": "}
        {shown.map(show).join(", ")}
        {rows.length > shown.length && `, and ${(rows.length - shown.length).toLocaleString()} more`}
      </span>
    </li>
  );
}

/**
 * The check step (owner 2026-11-26, 5yxn4w): what a chosen file would do to the regions stored
 * now, before anything is stored. A file with errors cannot be stored; the rows to fix are named
 * by line.
 */
const checkRegionFile: UploadPreview = async (csv) => {
  const records = parseCsvRecords(csv);
  const [header, ...rows] = records;
  const preview = previewRegionUpload(header?.fields ?? [], rows, await fetchStoredRegions());
  const canStore = preview.errors.length === 0 && preview.rows > 0;
  const summary = (
    <div className="space-y-2" data-region-upload-check="">
      <ul className="space-y-1">
        <li>
          <span className="font-medium tabular-nums">{preview.rows.toLocaleString()}</span> rows in the file
        </li>
        <ChangeList title="new regions" rows={preview.added} show={(r) => `${r.path} ${r.name}`} />
        <ChangeList title="names changed" rows={preview.renamed} show={(r) => `${r.path} ${r.oldName} → ${r.name}`} />
        <ChangeList title="get coordinates" rows={preview.coordinatesSet} show={(r) => `${r.path} ${r.name}`} />
        <ChangeList title="coordinates moved" rows={preview.coordinatesMoved} show={(r) => `${r.path} ${r.name}`} />
        {preview.unchanged > 0 && (
          <li>
            <span className="font-medium tabular-nums">{preview.unchanged.toLocaleString()}</span> unchanged
          </li>
        )}
        {preview.notInFile > 0 && (
          <li>
            <span className="font-medium tabular-nums">{preview.notInFile.toLocaleString()}</span> regions not in the
            file, which stay as they are
          </li>
        )}
      </ul>
      {preview.errors.length > 0 && (
        <div className="rounded border border-red-200 bg-red-50 p-2 text-red-800" data-region-upload-errors="">
          <p className="font-medium">
            {preview.errors.length.toLocaleString()} {preview.errors.length === 1 ? "row needs" : "rows need"} fixing
            before the file can be stored:
          </p>
          <ul className="mt-1 list-disc pl-5">
            {preview.errors.slice(0, 20).map((e) => (
              <li key={`${e.line}:${e.message}`}>
                Line {e.line}: {e.message}
              </li>
            ))}
          </ul>
          {preview.errors.length > 20 && <p>and {(preview.errors.length - 20).toLocaleString()} more.</p>}
        </div>
      )}
      {canStore && preview.added.length + preview.renamed.length + preview.coordinatesSet.length + preview.coordinatesMoved.length === 0 && (
        <p className="text-gray-600">The file changes nothing.</p>
      )}
    </div>
  );
  return { summary, canStore };
};

const RegionsCountDisplay = () => {
  const [numberOfRegions, refreshRegions] = useAtom(numberOfRegionsAtomAsync);

  const memoizedRefreshRelevantCounts = useCallback(async () => {
    refreshRegions(); // refreshRegions from useAtom is stable
  }, [refreshRegions]);

  return (
    <>
      {typeof numberOfRegions === 'number' && numberOfRegions > 0 && (
        <InfoBox>
          <div className="flex justify-between items-center">
            <p>There are already {numberOfRegions} regions defined</p>
            <Link
              href="/regions"
              target="_blank"
              className={buttonVariants({ variant: "outline" })}
            >
              View all
            </Link>
          </div>
        </InfoBox>
      )}
      <UploadCSVForm
        uploadView="region_upload"
        nextPage="/getting-started/upload-custom-sectors"
        refreshRelevantCounts={memoizedRefreshRelevantCounts}
        preview={checkRegionFile}
      />
    </>
  );
};

const RegionsCountSkeleton = () => (
  <>
    <div className="animate-pulse">
      <div className="h-10 bg-gray-200 rounded mb-4"></div> {/* Placeholder for InfoBox */}
    </div>
    {/* Placeholder for UploadCSVForm, or it can be outside Suspense if it doesn't depend on the count */}
    <div className="bg-ssb-light p-6 animate-pulse">
      <div className="h-6 bg-gray-200 rounded w-1/4 mb-4"></div> {/* Label */}
      <div className="h-10 bg-gray-200 rounded mb-4"></div> {/* Input */}
      <div className="h-10 bg-gray-200 rounded w-1/4"></div> {/* Button */}
    </div>
  </>
);

export default function UploadRegionsPage() {
  const client = useAtomValue(restClientAtom);
  // The Coordinates switch, as on the Regions list (owner 2026-11-26, 5yxn4w): off, the page tells
  // only what every country needs, path and name; on, also the coordinates. It starts on when any
  // region has a centre.
  const { data: anyCentre } = useSWR(client ? ["regions:any-centre"] : null, async () => {
    const { data: rows, error } = await client!.from("region").select("id").not("center_latitude", "is", null).limit(1);
    if (error) throw error;
    return (rows ?? []).length > 0;
  });
  const [chosen, setChosen] = useState<boolean | null>(null);
  const showCoordinates = chosen ?? anyCentre ?? false;

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Regions</h1>
      <p>
        Upload a CSV or Excel file with the regions you use in your analysis. The file is checked
        first: you see what it would add and change, and nothing is stored until you press Store.
      </p>
      <Suspense fallback={<RegionsCountSkeleton />}>
        <RegionsCountDisplay />
      </Suspense>
      <section className="space-y-3" data-upload-regions-file="">
        {/* The Coordinates switch on the heading of what it changes, the file's description (owner
            2026-11-26): the upload itself takes coordinates either way. */}
        <div className="flex items-center justify-between border-b pb-2">
          <h2 className="font-medium">What is a regions file?</h2>
          <div className="flex items-center gap-2">
            <Label htmlFor="upload-regions-coordinates">Coordinates</Label>
            <Switch
              id="upload-regions-coordinates"
              checked={showCoordinates}
              onCheckedChange={setChosen}
              data-upload-regions-coordinates=""
            />
          </div>
        </div>
        <div className="space-y-3 text-sm">
            {/* The columns every country needs, and the coordinates with the switch on. The columns
                are those of the view public.region_upload. */}
            <p className="mb-1">
              One row per region, with {showCoordinates ? "these columns" : "two columns"}:
            </p>
            <ul className="list-disc pl-6">
              <li>
                <code>path</code>: the region&apos;s code, with its parent&apos;s code in front,
                separated by a dot (<code>46</code> for a county, <code>46.4601</code> for a
                municipality in it). A parent comes before its children.
              </li>
              <li>
                <code>name</code>: the region&apos;s name.
              </li>
              {showCoordinates && (
                <>
                  <li>
                    <code>center_latitude</code>: degrees north, from -90 to 90, up to six decimals.
                  </li>
                  <li>
                    <code>center_longitude</code>: degrees east, from -180 to 180, up to six decimals.
                  </li>
                  <li>
                    <code>center_altitude</code>: metres above sea level, zero or more, one
                    decimal. Optional.
                  </li>
                </>
              )}
            </ul>
            {/* A file changes only what it gives (admin.region_upload_upsert, test/sql/414). */}
            <p>
              A file changes only what it gives. Regions not in the file, and cells left empty,
              keep what they have.
              {showCoordinates && (
                <>
                  {" "}
                  To add coordinates to the regions you have, a file of <code>path</code> and the
                  coordinate columns is enough; the names stay. Start from the regions you have (View all,
                  then Download as CSV or Excel), fill in the coordinates you know, and upload it here. One region at a time:
                  Regions, with Coordinates on, has Edit on each row, and the Regions map has it on
                  the selected region; a centre is removed there.
                </>
              )}
            </p>
            <div className="flex flex-col gap-1">
              <ExampleDownloads csvHref="/demo/regions_demo.csv" label="Example file" />
              {showCoordinates && (
                <ExampleDownloads
                  csvHref="/demo/regions_with_centre_demo.csv"
                  label="Example file of coordinates for listed regions"
                />
              )}
            </div>
        </div>
      </section>
    </section>
  );
}
