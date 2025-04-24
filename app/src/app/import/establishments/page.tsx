"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React from "react";
import { InfoBox } from "@/components/info-box";
import { useImportUnits } from "../import-units-context";
import { TimeContextSelector } from "../components/time-context-selector";
import { ImportJobCreator } from "../components/import-job-creator";

export default function UploadEstablishmentsPage() {
  const { counts: { establishmentsWithLegalUnit } } = useImportUnits();

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Establishments</h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {!!establishmentsWithLegalUnit &&
        establishmentsWithLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {establishmentsWithLegalUnit} formal
              establishments defined
            </p>
          </InfoBox>
        )}

      <TimeContextSelector unitType="establishments" />
      
      <ImportJobCreator 
        definitionSlug="establishment_for_lu_current_year"
        uploadPath="/import/establishments/upload"
        unitType="Establishments"
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Establishments">
          <AccordionTrigger>
            What is a Formal Establishment? (With corresponding Legal Unit)
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              This option must be used when your establishment file contain a
              column referring to legal_unit_ids already loaded. This option
              should only be used when your data has ids for both establishments
              and legal units. One establishment needs to connect to one legal
              unit, several establishments can connect to the same legal unit.
            </p>
            <p className="mb-3">
              An <i>Establishment</i> is typically defined as the smallest unit
              of a business or organization that is capable of organizing its
              production or services and can report on its activities
              separately. Here are key characteristics of an establishment:
            </p>
            <p className="mb-3">
              <strong>Physical Location:</strong> An establishment is usually
              characterized by having a single physical location. If a business
              operates in multiple places, each place may be considered a
              separate establishment.
            </p>
            <p className="mb-3">
              <strong>Economic Activity:</strong> It engages in one, or
              predominantly one, kind of economic activity. This means that the
              establishment&#39;s primary business activity should be classified
              under a specific category in the NACE / ISIC classification.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Establishments File">
          <AccordionTrigger>
            What is a Formal Establishments file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Formal Establishments file is a CSV file containing the
              establishments with relationship to its legal unit. Ids for both
              columns are required, and cannot contain any null values. Have a
              look at this example CSV file to get an idea of how the file
              should be structured:
            </p>
            <a
              href="/demo/formal_establishments_units_demo.csv"
              download="formal_establishments.example.csv"
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
