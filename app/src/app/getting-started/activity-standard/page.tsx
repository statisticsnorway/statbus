import React from "react";
import CategoryStandardForm from "@/app/getting-started/activity-standard/category-standard-form";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { getServerClient } from "@/context/ClientStore";

export default async function ActivityStandardPage() {
  const client = await getServerClient();

  const { data: standards } = await client
    .from("activity_category_standard")
    .select()
    .order("code")

  const { data: settings } = await client.from("settings").select();

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">
        Select Activity Category Standard
      </h1>
      <p>
        Select the activity category standard that best fit you location. If
        you&apos;re not sure which standard is the best fit, you can read more
        about the standards below.
      </p>
      <CategoryStandardForm standards={standards} settings={settings} />
      <Accordion type="single" collapsible>
        <AccordionItem value="Activity Category Standard">
          <AccordionTrigger>
            What is an Activity Category Standard?
          </AccordionTrigger>
          <AccordionContent>
            Activity category standards like NACE and ISIC organize economic
            activities into sectors for systematic analysis.
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="NACE">
          <AccordionTrigger>What is NACE?</AccordionTrigger>
          <AccordionContent>
            <strong>NACE</strong> (Statistical Classification of Economic
            Activities in the European Community) is a standard classification
            system used in the European Union to categorize economic activities.
            It provides a hierarchical structure that classifies businesses and
            economic activities into different sectors based on their primary
            activities. NACE is described in more detail on{" "}
            <a
              className="underline"
              href="https://ec.europa.eu/eurostat/web/nace"
            >
              ec.europa.eu
            </a>
            .
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="ISIC">
          <AccordionTrigger>What is ISIC?</AccordionTrigger>
          <AccordionContent>
            <strong>ISIC</strong> (International Standard Industrial
            Classification of All Economic Activities) is a globally accepted
            standard for classifying economic activities. Developed by the
            United Nations, ISIC is used to group economic activities at various
            levels, enabling consistent and comparable analysis of economic data
            and statistics across countries. ISIC is described in more detail on{" "}
            <a
              className="underline"
              href="https://unstats.un.org/unsd/classifications/Econ/isic"
            >
              unstats.un.org
            </a>
            .
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
