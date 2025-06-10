"use client";

import React from "react";
import { useGettingStartedManager as useGettingStarted } from '@/atoms/hooks';
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

export default function UploadRegionsPage() {
  const { dataState, refreshAllData } = useGettingStarted();
  const { numberOfRegions } = dataState;

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Region Hierarchy</h1>
      <p>
        Upload a CSV file containing the regions you want to use in your
        analysis.
      </p>

      {!!numberOfRegions && numberOfRegions > 0 && (
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
        refreshRelevantCounts={refreshAllData}
      />

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
