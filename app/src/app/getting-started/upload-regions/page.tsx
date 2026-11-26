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
                2026-11-22, 5yxn4w): the upload takes the centre columns either way. The
                columns are those of the view public.region_upload. */}
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
          <AccordionTrigger>Advanced: the region&apos;s centre</AccordionTrigger>
          <AccordionContent>
            <p className="mb-1">
              A region may also have a centre, which places it on the maps. Add any of these
              columns; a row may leave them empty.
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
              </li>
            </ul>
            <p className="mb-3">
              A region without a centre can be placed later on the Regions page, with Place on map.
            </p>
            <a
              href="/demo/regions_with_centre_demo.csv"
              download="regions_with_centre_demo.csv"
              className="underline"
            >
              Download example CSV file with centres
            </a>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
