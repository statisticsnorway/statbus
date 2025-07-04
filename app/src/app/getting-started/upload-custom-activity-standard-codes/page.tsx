"use client";

import React, { Suspense } from "react"; // Added Suspense
import { useAtom } from 'jotai'; // Added useAtom
import { numberOfCustomActivityCodesAtomAsync } from '@/atoms/getting-started'; // Added specific atom
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";

const CustomActivityCodesCountDisplay = () => {
  const [numberOfCustomActivityCategoryCodes, refreshCodesCount] = useAtom(numberOfCustomActivityCodesAtomAsync);

  return (
    <>
      {typeof numberOfCustomActivityCategoryCodes === 'number' && numberOfCustomActivityCategoryCodes > 0 && (
        <InfoBox>
          <div className="flex justify-between items-center">
            <p>
              There are already {numberOfCustomActivityCategoryCodes} custom
              activity category codes defined
            </p>
            <Link
              href="/activity-categories?custom=true"
              target="_blank"
              className={buttonVariants({ variant: "outline" })}
            >
              View all
            </Link>
          </div>
        </InfoBox>
      )}
      <UploadCSVForm
        uploadView="activity_category_available_custom"
        nextPage="/getting-started/upload-regions"
        refreshRelevantCounts={async () => refreshCodesCount()}
      />
    </>
  );
};

const CountSkeleton = () => (
  <>
    <div className="animate-pulse">
      <div className="h-10 bg-gray-200 rounded mb-4"></div> {/* Placeholder for InfoBox */}
    </div>
    <div className="bg-ssb-light p-6 animate-pulse">
      <div className="h-6 bg-gray-200 rounded w-1/4 mb-4"></div> {/* Label */}
      <div className="h-10 bg-gray-200 rounded mb-4"></div> {/* Input */}
      <div className="h-10 bg-gray-200 rounded w-1/4"></div> {/* Button */}
    </div>
  </>
);

export default function UploadCustomActivityCategoryCodesPage() {
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">
        Upload Custom Activity Category Standard Codes
      </h1>
      <p>
        Upload a CSV file containing the custom activity category standard codes
        you want to use in your analysis.
      </p>
      <Suspense fallback={<CountSkeleton />}>
        <CustomActivityCodesCountDisplay />
      </Suspense>
      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>
            What is a Custom Activity Category Code?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <i>Custom Activity Category Code</i> is a code that you can use
              to categorize economic activities and units for statistical and
              analytical purposes. It is a category code that is not part of the
              standard classification systems like NACE or ISIC and may be
              specific to your country.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>
            What is a Custom Activity Categories file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Custom Activity Categories file is a CSV file containing the
              Custom Activity Categories you want to use in your analysis. The
              file must conform to a specific format in order to be processed
              correctly. Have a look at this example CSV file to get an idea of
              how the file should be structured:
            </p>
            <a
              href="/demo/activity_custom_isic_demo.csv"
              download="custom_activity_categories.example.csv"
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
