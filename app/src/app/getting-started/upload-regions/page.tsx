"use client";

import React, { Suspense, useCallback } from "react"; // Added useCallback
import { useAtom } from 'jotai';
import { numberOfRegionsAtomAsync } from '@/atoms/getting-started';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { fetchWithAuth, getBrowserRestClient } from "@/context/RestClientStore";

/**
 * The regions as an upload file (path, name and the centre columns, as public.region_upload reads
 * them), so an office fills in coordinates and uploads it again (owner 2026-11-26, 5yxn4w).
 */
function RegionsDownloadLink() {
  const [error, setError] = React.useState<string | null>(null);
  const download = async () => {
    setError(null);
    try {
      const client = await getBrowserRestClient();
      const response = await fetchWithAuth(`${client.url}/region_upload`, { headers: { Accept: "text/csv" } });
      if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
      const url = URL.createObjectURL(new Blob([await response.text()], { type: "text/csv" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = "regions.csv";
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };
  return (
    <>
      <button type="button" className="underline" onClick={() => void download()} data-upload-regions-download="">
        Download the regions you have
      </button>
      {error && <span className="text-red-700">The download failed: {error}</span>}
    </>
  );
}

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
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Regions</h1>
      <p>
        Upload a CSV file containing the regions you want to use in your
        analysis.
      </p>
      <Suspense fallback={<RegionsCountSkeleton />}>
        <RegionsCountDisplay />
      </Suspense>
      <Accordion type="single" collapsible>
        <AccordionItem value="Activity Category Standard">
          <AccordionTrigger>What is a Regions file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A regions file is a CSV file containing the regions you want to
              use in your analysis. The file must conform to a specific format
              in order to be processed correctly.
            </p>
            {/* The columns every country needs, then the optional centre under Advanced (owner
                2026-11-22, 5yxn4w). The columns are those of the view public.region_upload. */}
            <p className="mb-1">Each row has two columns:</p>
            <ul className="mb-3 list-disc pl-6">
              <li>
                <code>path</code>: the region&apos;s code, with its parent&apos;s code in front,
                separated by a dot (<code>46</code> for a county, <code>46.4601</code> for a
                municipality in it). A parent comes before its children.
              </li>
              <li>
                <code>name</code>: the region&apos;s name.
              </li>
            </ul>
            <a
              href="/demo/regions_demo.csv"
              download="regions_demo.csv"
              className="underline"
            >
              Download example CSV file
            </a>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Advanced" data-upload-regions-advanced="">
          <AccordionTrigger>Advanced: the regions&apos; coordinates</AccordionTrigger>
          <AccordionContent>
            {/* A file changes only what it gives (owner 2026-11-26, 5yxn4w;
                admin.region_upload_upsert): coordinates can come in a file of their own, for the
                regions already listed, and a later list of names keeps them. */}
            <p className="mb-1">
              A region&apos;s centre places it on the maps. Add these columns to the file:
            </p>
            <ul className="mb-3 list-disc pl-6">
              <li>
                <code>center_latitude</code>: degrees north, from -90 to 90, up to six decimals.
              </li>
              <li>
                <code>center_longitude</code>: degrees east, from -180 to 180, up to six decimals.
              </li>
              <li>
                <code>center_altitude</code>: metres above sea level, zero or more, one decimal.
                Optional.
              </li>
            </ul>
            <p className="mb-1 font-medium">Adding coordinates to the regions you have</p>
            <p className="mb-3">
              A file changes only what it gives. For regions already listed, a file of{" "}
              <code>path</code> and the coordinate columns adds their centres; the names stay.
              Rows you leave empty, and regions not in the file, keep what they have, and a later
              file of only <code>path</code> and <code>name</code> keeps the centres. Start from
              the regions you have, fill in the coordinates you know, and upload it here.
            </p>
            <p className="mb-3 flex flex-wrap gap-x-4 gap-y-1">
              <RegionsDownloadLink />
              <a
                href="/demo/regions_with_centre_demo.csv"
                download="regions_with_centre_demo.csv"
                className="underline"
              >
                Download an example file with coordinates
              </a>
            </p>
            <p>
              One region at a time: Regions, with Coordinates switched on, has Edit on each row,
              and the Regions map has it on the selected region. Removing a centre is done there.
            </p>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
