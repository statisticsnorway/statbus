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

export default function UploadEstablishmentsPage() {
  const {
    numberOfEstablishmentsWithLegalUnit,
    refreshNumberOfEstablishmentsWithLegalUnit,
  } = useImportUnits();

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Establishments</h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {!!numberOfEstablishmentsWithLegalUnit &&
        numberOfEstablishmentsWithLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {numberOfEstablishmentsWithLegalUnit}{" "}
              establishments defined
            </p>
          </InfoBox>
        )}

      <UploadCSVForm
        uploadView="import_establishment_current_for_legal_unit"
        nextPage="/import/establishments-without-legal-unit"
        refreshRelevantCounts={refreshNumberOfEstablishmentsWithLegalUnit}
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
              href="/underenheter-selection-web-import.csv"
              download="establishments.example.csv"
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
