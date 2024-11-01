"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React from "react";
import { InfoBox } from "@/components/info-box";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import { useImportUnits } from "../import-units-context";

export default function UploadLegalUnitsPage() {
  const { numberOfLegalUnits, refreshNumberOfLegalUnits } = useImportUnits();

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Units</h1>
      <p>
        Upload a CSV file containing Legal Units you want to use in your
        analysis.
      </p>

      {!!numberOfLegalUnits && numberOfLegalUnits > 0 && (
        <InfoBox>
          <p>There are already {numberOfLegalUnits} legal units defined</p>
        </InfoBox>
      )}

      <UploadCSVForm
        uploadView="import_legal_unit_current"
        nextPage="/import/establishments"
        refreshRelevantCounts={refreshNumberOfLegalUnits}
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>What is a Legal Unit?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <strong>Legal Unit</strong> refers to an entity or establishment
              that is considered an individual economic unit engaged in economic
              activities. Both NACE and ISIC are classification systems used to
              categorize economic activities and units for statistical and
              analytical purposes. They provide a framework to classify
              different economic activities and units based on their primary
              activities.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>What is a Legal Units file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Legal Units file is a CSV file containing the Legal Units you
              want to use in your analysis. The file must conform to a specific
              format in order to be processed correctly. Have a look at this
              example CSV file to get an idea of how the file should be
              structured:
            </p>
            <a
              href="/legal_units_demo.csv"
              download="legalunits.example.csv"
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
