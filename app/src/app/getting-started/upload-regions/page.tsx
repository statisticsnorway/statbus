import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import {Button, buttonVariants} from "@/components/ui/button";
import {uploadRegions} from "@/app/getting-started/upload-regions/actions";
import {createClient} from "@/lib/supabase.server.client";
import Link from "next/link";
import {Accordion, AccordionContent, AccordionItem, AccordionTrigger} from "@/components/ui/accordion";
import React from "react";
import {InfoBox} from "@/components/InfoBox";

export default async function UploadRegionsPage() {
  const client = createClient()
  const {data: regions} = await client.from('region').select('id, name')
  return (
    <section className="space-y-8">
      <h1 className="text-xl text-center">Upload Regions</h1>
      <p>Upload a CSV file containing the regions you want to use in your analysis.</p>

      {
        regions?.length ? (
          <InfoBox>
            <p>
              There are already {regions.length} regions defined. You may skip this step.
            </p>
          </InfoBox>
        ) : null
      }

      <form action={uploadRegions} className="space-y-6 bg-green-100 p-6">
        <Label className="block" htmlFor="regions-file">Select regions file:</Label>
        <Input required id="regions-file" type="file" name="regions"/>
        <div className="space-x-3">
          <Button type="submit">Upload</Button>
          <Link href="/getting-started/upload-legal-units" className={buttonVariants({variant: 'outline'})}>Skip</Link>
        </div>
      </form>

      <Accordion type="single" collapsible>
        <AccordionItem value="Activity Category Standard">
          <AccordionTrigger>What is a Regions file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A regions file is a CSV file containing the regions you want to use in your analysis. The file
              must conform to a specific format in order to be processed correctly.
            </p>
            <a href="/norway-sample-regions.csv" download="regions.example.csv" className="underline">Download example
              CSV file</a>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  )
}
