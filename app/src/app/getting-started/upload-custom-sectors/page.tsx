import React from "react";
import { InfoBox } from "@/components/info-box";
import { createSupabaseServerClient } from "@/utils/supabase/server";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export default async function UploadCustomSectorsPage() {
  const client = await createSupabaseServerClient();
  const { count } = await client
    .from("sector_custom")
    .select("*", { count: "exact", head: true })
    .limit(0);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Sectors</h1>
      <p>
        Upload a CSV file containing the custom sectors you want to use in your
        analysis.
      </p>

      {count && count > 0 ? (
        <InfoBox>
          <p>There are already {count} custom sectors defined</p>
        </InfoBox>
      ) : null}

      <UploadCSVForm
        uploadView="sector_custom_only"
        nextPage="/getting-started/upload-custom-legal-forms"
      />

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
              href="/sector_norway.csv"
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
