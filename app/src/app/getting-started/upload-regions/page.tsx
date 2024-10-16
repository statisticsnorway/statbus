import React from "react";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { InfoBox } from "@/components/info-box";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";

export default async function UploadRegionsPage() {
  const client = await createSupabaseSSRClient();
  const { count } = await client
    .from("region")
    .select("*", { count: "exact", head: true })
    .limit(0);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Regions</h1>
      <p>
        Upload a CSV file containing the regions you want to use in your
        analysis.
      </p>

      {count && count > 0 ? (
        <InfoBox>
          <p>There are already {count} regions defined</p>
        </InfoBox>
      ) : null}

      <UploadCSVForm
        uploadView="region_upload"
        nextPage="/getting-started/upload-custom-sectors"
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
              href="/norway-regions-2024.csv"
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
