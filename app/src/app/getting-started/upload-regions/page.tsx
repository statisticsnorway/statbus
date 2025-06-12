"use client";

import React, { Suspense } from "react";
import { useAtom } from 'jotai';
import { numberOfRegionsAtomAsync } from '@/atoms';
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
        refreshRelevantCounts={async () => refreshRegions()}
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
      <h1 className="text-center text-2xl">Upload Region Hierarchy</h1>
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
            <a
              href="/demo/regions_demo.csv"
              download="regions.example.csv"
              className="underline"
            >
              Download example CSV file
            </a>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
