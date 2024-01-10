import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import {Button, buttonVariants} from "@/components/ui/button";
import {createClient} from "@/lib/supabase.server.client";
import {Accordion, AccordionContent, AccordionItem, AccordionTrigger} from "@/components/ui/accordion";
import {uploadLegalUnits} from "@/app/getting-started/upload-legal-units/actions";
import React from "react";
import Link from "next/link";
import {InfoBox} from "@/components/InfoBox";

export default async function UploadRegionsPage() {
  const client = createClient()
  const {data: legalUnits} = await client.from('legal_unit').select('id, name')
  return (
    <section className="space-y-8">
      <h1 className="text-xl text-center">Upload Legal Units</h1>
      <p>
        Upload a CSV file containing Legal Units you want to use in your analysis.
      </p>

      {
        legalUnits?.length ? (
          <InfoBox>
            <p>
              There are already {legalUnits.length} legal units defined. You may skip this step.
            </p>
          </InfoBox>
        ) : null
      }

      <form action={uploadLegalUnits} className="space-y-6 bg-green-100 p-6">
        <Label className="block" htmlFor="regions-file">Select Legal Units file:</Label>
        <Input required id="regions-file" type="file" name="regions"/>
        <div className="space-x-3">
          <Button type="submit">Upload</Button>
          <Link href="/getting-started/summary" className={buttonVariants({ variant: 'outline' })}>Skip</Link>
        </div>
      </form>

      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>What is a Legal Unit?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <strong>Legal Unit</strong> refers to an entity or establishment that is considered an individual economic unit engaged in economic activities.

              Both NACE and ISIC are classification systems used to categorize economic activities and units for statistical and analytical purposes.
              They provide a framework to classify different economic activities and units based on their primary activities.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>What is a Legal Units file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Legal Units file is a CSV file containing the Legal Units you want to use in your analysis. The file
              must conform to a specific format in order to be processed correctly. Have a look at this example
              CSV file to get an idea of how the file should be structured:
            </p>
            <a href="/100BREGUnits.csv" download="legalunits.example.csv" className="underline">Download example CSV file</a>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  )
}
