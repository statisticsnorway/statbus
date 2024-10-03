import React from "react";
import { InfoBox } from "@/components/info-box";
import { createClient } from "@/utils/supabase/server";
import { UploadCSVForm } from "@/app/getting-started/upload-csv-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export default async function UploadCustomActivityCategoryCodesPage() {
  const client = createClient();
  const { count } = await client
    .from("activity_category_available_custom")
    .select("*", { count: "exact", head: true })
    .limit(0);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">
        Upload Custom Activity Category Standard Codes
      </h1>
      <p>
        Upload a CSV file containing the custom activity category standard codes
        you want to use in your analysis.
      </p>

      {count && count > 0 ? (
        <InfoBox>
          <p>
            There are already {count} custom activity category codes defined
          </p>
        </InfoBox>
      ) : null}

      <UploadCSVForm
        uploadView="activity_category_available_custom"
        nextPage="/getting-started/upload-legal-units"
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>
            What is a Custom Activity Category Code?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <i>Custom Activity Category Code</i> is a code that you can use
              to categorize economic activities and units for statistical and
              analytical purposes. It is a category code that is not part of the
              standard classification systems like NACE or ISIC and may be
              specific to your country.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>
            What is a Custom Activity Categories file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Custom Activity Categories file is a CSV file containing the
              Custom Activity Categories you want to use in your analysis. The
              file must conform to a specific format in order to be processed
              correctly. Have a look at this example CSV file to get an idea of
              how the file should be structured:
            </p>
            <a
              href="/activity_category_norway.csv"
              download="custom_activity_categories.example.csv"
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
