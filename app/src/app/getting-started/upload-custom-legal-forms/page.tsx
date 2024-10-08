import React from "react";
import { InfoBox } from "@/components/info-box";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export default async function UploadCustomSectorsPage() {
  const client = await createSupabaseSSRClient();
  const { count } = await client
    .from("legal_form_custom")
    .select("*", { count: "exact", head: true })
    .limit(0);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Forms</h1>
      <p>
        Upload a CSV file containing the custom legal forms you want to use in
        your analysis.
      </p>

      {count && count > 0 ? (
        <InfoBox>
          <p>There are already {count} custom legal forms defined</p>
        </InfoBox>
      ) : null}

      <UploadCSVForm
        uploadView="legal_form_custom_only"
        nextPage="/getting-started/upload-custom-activity-standard-codes"
      />

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
              href="/legal_form_norway.csv"
              download="legal_form.example.csv"
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
