"use client";

import React, { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useImportManager, usePendingJobsByPattern } from "@/atoms/hooks"; // Updated import
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
  const { counts } = useImportManager();
  // Use the generalized hook with the specific slug pattern for legal units
  const { jobs: pendingJobs, loading: isLoading, error, refreshJobs } = usePendingJobsByPattern("%legal_unit%");
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  // The useEffect in usePendingJobsByPattern handles initial fetch.
  // If a manual refresh on mount is still desired for some reason, it can be added here,
  // but typically the hook's internal logic should suffice.
  // useEffect(() => {
  //   refreshJobs();
  // }, [refreshJobs]); // This might cause a double fetch if the hook also fetches.

  const handleDeleteJob = async (jobId: number) => {
    if (window.confirm("Are you sure you want to cancel and delete this import job? This action cannot be undone.")) {
      try {
        const client = await getBrowserRestClient();
        const { error } = await client.from("import_job").delete().eq("id", jobId);
        if (error) {
          throw error;
        }
        refreshJobs(); // Refresh the list after deletion
      } catch (err: any) {
        console.error("Failed to delete import job:", err);
        alert(`Error deleting job: ${err.message}`);
      }
    }
  };

  if (isLoading && pendingJobs.length === 0) {
    return <Spinner message="Checking for existing import jobs..." />;
  }

  if (error) {
    return <InfoBox variant="error"><p>Error loading pending jobs: {error}</p></InfoBox>;
  }

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Units</h1>
      <p>
        Upload a CSV file containing Legal Units you want to use in your
        analysis.
      </p>

      {isClient && !!counts.legalUnits && counts.legalUnits > 0 && (
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
                <div className="flex items-center space-x-2">
                  <Button 
                    size="sm"
                    onClick={() => router.push(`/import/legal-units/upload/${job.slug}`)}
                  >
                    Continue
                  </Button>
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleDeleteJob(job.id)}
                  >
                    Cancel
                  </Button>
                </div>
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
        onJobCreated={refreshJobs}
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
