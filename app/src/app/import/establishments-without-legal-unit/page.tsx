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

export default function UploadEstablishmentsWithoutLegalUnitPage() {
  const {
    numberOfEstablishmentsWithoutLegalUnit,
    refreshNumberOfEstablishmentsWithoutLegalUnit,
  } = useImportUnits();
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">
        Upload Establishments Without Legal Unit
      </h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {!!numberOfEstablishmentsWithoutLegalUnit &&
        numberOfEstablishmentsWithoutLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {numberOfEstablishmentsWithoutLegalUnit}{" "}
              establishments defined
            </p>
          </InfoBox>
        )}

      <UploadCSVForm
        uploadView="import_establishment_current_without_legal_unit"
        nextPage="/import/analyse-data-for-search-and-reports"
        refreshRelevantCounts={refreshNumberOfEstablishmentsWithoutLegalUnit}
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Establishments">
          <AccordionTrigger>
            What is an Informal Establishment? (Without corresponding Legal
            Unit)
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              This option is typically used for surveys /censuses of informal
              economy. There is no column pointing to any legal units in this
              file.
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
            What is an Informal Establishments file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              An Informal Establishments file is a CSV file containing the
              establishments independent of legal units. Only ids for the
              establishments should be presented in this option. Have a look at
              this example CSV file to get an idea of how the file should be
              structured:
            </p>
            <a
              href="/informal_establishments_units_demo.csv"
              download="informalestablishments.example.csv"
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
