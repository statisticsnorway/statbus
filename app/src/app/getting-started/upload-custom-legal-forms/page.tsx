"use client";

import React, { Suspense } from "react"; // Added Suspense
import { useAtom } from 'jotai'; // Added useAtom
import { numberOfCustomLegalFormsAtomAsync } from '@/atoms/getting-started'; // Added specific atom
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

const CustomLegalFormsCountDisplay = () => {
  const [numberOfCustomLegalForms, refreshLegalFormsCount] = useAtom(numberOfCustomLegalFormsAtomAsync);

  return (
    <>
      {typeof numberOfCustomLegalForms === 'number' && numberOfCustomLegalForms > 0 && (
        <InfoBox>
          <p>
            There are already {numberOfCustomLegalForms} custom legal forms
            defined
          </p>
        </InfoBox>
      )}
      <UploadCSVForm
        uploadView="legal_form_custom_only"
        nextPage="/getting-started/summary"
        refreshRelevantCounts={async () => refreshLegalFormsCount()}
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

export default function UploadCustomLegalFormsPage() { // Renamed component function for clarity
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Forms</h1>
      <p>
        Upload a CSV file containing the custom legal forms you want to use in
        your analysis.
      </p>
      <Suspense fallback={<CountSkeleton />}>
        <CustomLegalFormsCountDisplay />
      </Suspense>
      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>What is a Legal Form?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <i>legal form</i> refers to the official classification or
              structure under which a business or organization operates within
              the legal framework of a country. This classification determines
              the legal responsibilities, governance structures, tax
              obligations, and the way the entity interacts with stakeholders,
              regulatory bodies, and the government. Legal forms can vary
              significantly, ranging from sole proprietorships and partnerships
              to corporations and non-profit organizations. Each legal form has
              specific requirements for registration, record-keeping, and
              operational conduct, which can influence the entity&#39;s capacity
              to raise funds, its liability exposure, and its overall
              operational flexibility. Selecting the appropriate legal form is a
              critical decision for any entity, affecting its legal identity,
              autonomy, and the legal protections afforded to its owners and
              operators.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>What is a Legal Forms file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              The contents of a legal form CSV file typically include a
              comprehensive list of various legal forms recognized within a
              jurisdiction, often used by business registries and statistical
              offices to categorize and manage information about entities
              operating in the economy. Each entry in the file usually consists
              of a code and a name describing a specific legal form, such as
              sole proprietorship, partnership, limited liability company, or
              non-profit organization. For example, entries like &#34;AS&#34;
              for Aksjeselskap (corporation) or &#34;ENK&#34; for
              Enkeltpersonforetak (sole proprietorship) provide a standardized
              way to refer to these entities across administrative and legal
              processes. This CSV file serves as a crucial reference for
              entities registering their business, ensuring that they are
              correctly classified according to the legal structure they adopt.
              It aids in the uniformity and clarity of business registration
              processes, statistical analysis, and international comparisons of
              business environments.
            </p>
            <a
              href="/demo/legal_forms_demo.csv"
              download="legal_forms_demo.csv"
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
