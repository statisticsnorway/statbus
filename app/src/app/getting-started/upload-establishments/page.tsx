import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React from "react";
import { InfoBox } from "@/components/info-box";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";

export default async function UploadEstablishmentsPage() {
  const client = await createSupabaseSSRClient();
  const { count } = await client
    .from("establishment")
    .select("*", { count: "exact", head: true })
    .limit(0);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Establishments</h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {count && count > 0 ? (
        <InfoBox>
          <p>There are already {count} establishments defined</p>
        </InfoBox>
      ) : null}

      <UploadCSVForm
        uploadView="import_establishment_current_for_legal_unit"
        nextPage="/getting-started/analyse-data-for-search-and-reports"
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Establishments">
          <AccordionTrigger>What is an Establishment?</AccordionTrigger>
          <AccordionContent>
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
              establishment&#39;s primary business activity can be classified
              under a specific category in the NACE or similar industry
              classification system.
            </p>
            <p>
              <strong>Operational Independence:</strong> Although it might be
              part of a larger enterprise, an establishment typically has a
              degree of operational independence, especially in terms of its
              production processes, management, and reporting.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Establishments File">
          <AccordionTrigger>What is an Establishments file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              An Establishments file is a CSV file containing the establishments
              you want to use in your analysis. The file must conform to a
              specific format in order to be processed correctly. Have a look at
              this example CSV file to get an idea of how the file should be
              structured:
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
