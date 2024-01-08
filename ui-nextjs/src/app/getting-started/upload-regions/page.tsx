import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import {Button} from "@/components/ui/button";
import {uploadRegions} from "@/app/getting-started/upload-regions/actions";
import {createClient} from "@/lib/supabase.server.client";
import Link from "next/link";
import {Accordion, AccordionContent, AccordionItem, AccordionTrigger} from "@/components/ui/accordion";
import React from "react";

export default async function UploadRegionsPage() {
    const client = createClient()
    const {data: regions} = await client.from('region').select('id, name')
    return (
        <section className="space-y-8">
            <h1 className="text-xl text-center">Upload regions</h1>
            <p>Upload a CSV file containing the regions you want to use in your analysis.</p>
            <form action={uploadRegions} className="space-y-3 bg-green-100 p-6">
                <Label className="block" htmlFor="regions-file">Select regions file</Label>
                <Input required id="regions-file" type="file" name="regions"/>
                <Button type="submit">Next</Button>
            </form>

            {
                regions?.length ? (
                    <>
                        <p>There are <strong>{regions.length}</strong> regions already defined.&nbsp;
                            <Link className="underline" href="/getting-started/summary">Continue -&gt;</Link>
                        </p>
                    </>
                ) : null
            }

            <Accordion type="single" collapsible>
                <AccordionItem value="Activity Category Standard">
                    <AccordionTrigger>What is a Regions file?</AccordionTrigger>
                    <AccordionContent>
                        A regions file is a CSV file containing the regions you want to use in your analysis. The file
                        must conform to a specific format in order to be processed correctly.
                    </AccordionContent>
                </AccordionItem>
            </Accordion>
        </section>
    )
}
