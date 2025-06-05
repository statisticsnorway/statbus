"use client";

import React, { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useImportUnits } from "../import-units-context";
import { ImportJobCreator } from "../components/import-job-creator";
import { TimeContextSelector } from "../components/time-context-selector";
import { Spinner } from "@/components/ui/spinner";
import { Button } from "@/components/ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { InfoBox } from "@/components/info-box";

export default function LegalUnitsPage() {
  const router = useRouter();
  // No longer need importState here
  const { counts } = useImportUnits(); 
  const [isLoading, setIsLoading] = useState(true);
  const [pendingJobs, setPendingJobs] = useState<Tables<"import_job">[]>([]);

  // Check for existing jobs
  useEffect(() => {
    const checkExistingJobs = async () => {
      // Removed redirection based on importState.currentJob
      
      try {
        // Check for any pending legal unit import jobs (state = 'waiting_for_upload')
        const client = await getBrowserRestClient();
        if (!client) throw new Error("Failed to get browser REST client");
        
        const { data, error } = await client
          .from("import_job")
          .select("*, import_definition!inner(*)")
          .eq("state", "waiting_for_upload")
          .like("import_definition.slug", "%legal_unit%")
          .order("created_at", { ascending: false });
        
        if (error) throw error;
        
        // Use the filtered data directly from the query
        const legalUnitJobs = data || [];
        
        setPendingJobs(legalUnitJobs);
      } catch (error) {
        console.error("Error checking for existing import jobs:", error);
      } finally {
        setIsLoading(false);
      }
    };

    checkExistingJobs();
    // Removed importState.currentJob from dependencies
  }, [router]); 

  if (isLoading) {
    return <Spinner message="Checking for existing import jobs..." />;
  }

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Units</h1>
      <p>
        Upload a CSV file containing Legal Units you want to use in your
        analysis.
      </p>

      {!!counts.legalUnits && counts.legalUnits > 0 && (
        <InfoBox>
          <p>There are already {counts.legalUnits} legal units defined</p>
        </InfoBox>
      )}

      {pendingJobs.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-md p-4 mb-6">
          <h3 className="font-medium mb-2">Pending Import Jobs</h3>
          <p className="text-sm mb-4">
            You have {pendingJobs.length} pending legal unit import {pendingJobs.length === 1 ? 'job' : 'jobs'} waiting for upload.
            Would you like to continue with one of these?
          </p>
          <div className="space-y-2">
            {pendingJobs.map(job => (
              <div key={job.id} className="flex justify-between items-center bg-white p-3 rounded border">
                <div>
                  <p className="font-medium">{job.description || "Legal Unit Import"}</p>
                  <p className="text-xs text-gray-500">Created: {new Date(job.created_at).toLocaleString()}</p>
                </div>
                <Button 
                  size="sm"
                  onClick={() => router.push(`/import/legal-units/upload/${job.slug}`)}
                >
                  Continue
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}

      <TimeContextSelector unitType="legal-units" />
      
      <ImportJobCreator 
        definitionSlug="legal_unit_current_year"
        uploadPath="/import/legal-units/upload"
        unitType="Legal Units"
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Unit">
          <AccordionTrigger>What is a Legal Unit?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <strong>Legal Unit</strong> refers to an entity or establishment
              that is considered an individual economic unit engaged in economic
              activities. Both NACE and ISIC are classification systems used to
              categorize economic activities and units for statistical and
              analytical purposes. They provide a framework to classify
              different economic activities and units based on their primary
              activities.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Units File">
          <AccordionTrigger>What is a Legal Units file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Legal Units file is a CSV file containing the Legal Units you
              want to use in your analysis. The file must conform to a specific
              format in order to be processed correctly. Have a look at this
              example CSV file to get an idea of how the file should be
              structured:
            </p>
            <a
              href="/demo/legal_units_demo.csv"
              download="legal_units.example.csv"
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
