"use client";

import React, { Suspense, useCallback } from "react"; // Added Suspense and useCallback
import { useAtom } from 'jotai'; // Added useAtom
import { numberOfCustomSectorsAtomAsync } from '@/atoms/getting-started'; // Added specific atom
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

const CustomSectorsCountDisplay = () => {
  const [numberOfCustomSectors, refreshSectorsCount] = useAtom(numberOfCustomSectorsAtomAsync);

  const memoizedRefreshSectorsCount = useCallback(async () => {
    refreshSectorsCount(); // refreshSectorsCount from useAtom is stable
  }, [refreshSectorsCount]);

  return (
    <>
      {typeof numberOfCustomSectors === 'number' && numberOfCustomSectors > 0 && (
        <InfoBox>
          <p>
            There are already {numberOfCustomSectors} custom sectors defined
          </p>
        </InfoBox>
      )}
      <UploadCSVForm
        uploadView="sector_custom_only"
        nextPage="/getting-started/upload-custom-legal-forms"
        refreshRelevantCounts={memoizedRefreshSectorsCount}
      />
    </>
  );
};

const CountSkeleton = () => ( // Re-using the same skeleton structure
  <>
    <div className="animate-pulse">
      <div className="h-10 bg-gray-200 rounded mb-4"></div>
    </div>
    <div className="bg-ssb-light p-6 animate-pulse">
      <div className="h-6 bg-gray-200 rounded w-1/4 mb-4"></div>
      <div className="h-10 bg-gray-200 rounded mb-4"></div>
      <div className="h-10 bg-gray-200 rounded w-1/4"></div>
    </div>
  </>
);

export default function UploadCustomSectorsPage() {
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Sectors</h1>
      <p>
        Upload a CSV file containing the custom sectors you want to use in your
        analysis.
      </p>
      <Suspense fallback={<CountSkeleton />}>
        <CustomSectorsCountDisplay />
      </Suspense>
      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>What is a Sector?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <i>sector</i> in the context of this discussion refers to a
              distinct subset within an economy or a field of business activity
              that shares common characteristics or functions. Sectors are
              classified to organize various types of business operations for
              analytical, regulatory, and reporting purposes. For instance, the
              classification can distinguish between financial and non-financial
              corporations, governmental operations, and entities with different
              forms of ownership and economic responsibilities. These
              classifications help in understanding the structure of the
              economy, making it easier to analyze data, perform surveys, and
              manage business registries at a national level.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>What is a Sectors file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              The sector CSV file is a structured data file that serves as a
              comprehensive register or database, designed to categorize
              different entities or organizations within an economy according to
              specific sectors. Each row in the file represents a unique sector
              or sub-sector and includes information such as a hierarchical path
              (indicating its position within a larger classification system), a
              name (a descriptive label for the sector), and a description that
              may include detailed notes about the sector scope,
              characteristics, and inclusion criteria. For example, it
              differentiates between non-financial and financial entities,
              outlines ownership types (such as state or privately owned), and
              specifies the nature of economic activities (market production vs.
              non-market activities). This file is instrumental for statistical
              offices in maintaining an up-to-date business registry, conducting
              business surveys, and producing national-level statistics, which
              in turn supports the comparison of economic data across countries
              using international standards.
            </p>
            <a
              href="/demo/sectors_demo.csv"
              download="sectors.example.csv"
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
