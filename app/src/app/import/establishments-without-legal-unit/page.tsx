"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React, { useState, useEffect } from "react";
import { InfoBox } from "@/components/info-box";
import { useImportManager } from "@/atoms/hooks"; // Updated import
import { TimeContextSelector } from "../components/time-context-selector";
import { ImportJobCreator } from "../components/import-job-creator";
import { Spinner } from "@/components/ui/spinner";
import { Button } from "@/components/ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import { useRouter } from "next/navigation";

export default function UploadEstablishmentsWithoutLegalUnitPage() {
  const router = useRouter();
  // No longer need importState here
  const { counts: { establishmentsWithoutLegalUnit } } = useImportManager(); // Updated hook call
  const [isLoading, setIsLoading] = useState(true);
  const [pendingJobs, setPendingJobs] = useState<Tables<"import_job">[]>([]);

  // Check for existing jobs
  useEffect(() => {
    const checkExistingJobs = async () => {
      // Removed redirection based on importState.currentJob

      try {
        // Check for any pending establishment without legal unit import jobs (state = 'waiting_for_upload')
        const client = await getBrowserRestClient();
        if (!client) throw new Error("Failed to get browser REST client");
        
        const { data, error } = await client
          .from("import_job")
          .select("*, import_definition!inner(*)")
          .eq("state", "waiting_for_upload")
          .like("import_definition.slug", "%establishment_without_lu%")
          .order("created_at", { ascending: false });
        
        if (error) throw error;
        
        // Use the filtered data directly from the query
        const establishmentJobs = data || [];
        
        setPendingJobs(establishmentJobs);
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
      <h1 className="text-center text-2xl">
        Upload Establishments Without Legal Unit
      </h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {!!establishmentsWithoutLegalUnit &&
        establishmentsWithoutLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {establishmentsWithoutLegalUnit}{" "}
              informal establishments defined
            </p>
          </InfoBox>
        )}

      {pendingJobs.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-md p-4 mb-6">
          <h3 className="font-medium mb-2">Pending Import Jobs</h3>
          <p className="text-sm mb-4">
            You have {pendingJobs.length} pending establishment import {pendingJobs.length === 1 ? 'job' : 'jobs'} waiting for upload.
            Would you like to continue with one of these?
          </p>
          <div className="space-y-2">
            {pendingJobs.map(job => (
              <div key={job.id} className="flex justify-between items-center bg-white p-3 rounded border">
                <div>
                  <p className="font-medium">{job.description || "Establishment Without Legal Unit Import"}</p>
                  <p className="text-xs text-gray-500">Created: {new Date(job.created_at).toLocaleString()}</p>
                </div>
                <Button 
                  size="sm"
                  onClick={() => router.push(`/import/establishments-without-legal-unit/upload/${job.slug}`)}
                >
                  Continue
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}

      <TimeContextSelector unitType="establishments-without-legal-unit" />
      
      <ImportJobCreator 
        definitionSlug="establishment_without_lu_current_year"
        uploadPath="/import/establishments-without-legal-unit/upload"
        unitType="Establishments Without Legal Unit"
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Establishments">
          <AccordionTrigger>
            What is an Informal Establishment? (Without corresponding Legal
            Unit)
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              This option is typically used for surveys /censuses of informal
              economy. There is no column pointing to any legal units in this
              file.
            </p>
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
              establishment&#39;s primary business activity should be classified
              under a specific category in the NACE / ISIC classification.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Establishments File">
          <AccordionTrigger>
            What is an Informal Establishments file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              An Informal Establishments file is a CSV file containing the
              establishments independent of legal units. Only ids for the
              establishments should be presented in this option. Have a look at
              this example CSV file to get an idea of how the file should be
              structured:
            </p>
            <a
              href="/demo/informal_establishments_units_demo.csv"
              download="informal_establishments.example.csv"
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
