"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React, { useEffect, useState } from "react";
import { InfoBox } from "@/components/info-box";
import { useImportManager, usePendingJobsByPattern } from "@/atoms/hooks";
import { TimeContextSelector } from "../components/time-context-selector";
import { ImportJobCreator } from "../components/import-job-creator";
import { Spinner } from "@/components/ui/spinner";
import { Button } from "@/components/ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import { useRouter } from "next/navigation";

export default function UploadEstablishmentsPage() {
  const router = useRouter();
  const { counts: { establishmentsWithLegalUnit } } = useImportManager();
  // Use the generalized hook with the specific slug pattern for establishments with LU
  const { jobs: pendingJobs, loading: isLoading, error, refreshJobs } = usePendingJobsByPattern("%establishment_for_lu%");
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  // The useEffect in usePendingJobsByPattern handles initial fetch.

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
      <h1 className="text-center text-2xl">Upload Establishments</h1>
      <p>
        Upload a CSV file containing the establishments you want to use in your
        analysis.
      </p>

      {isClient && !!establishmentsWithLegalUnit &&
        establishmentsWithLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {establishmentsWithLegalUnit} formal
              establishments defined
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
                  <p className="font-medium">{job.description || "Establishment Import"}</p>
                  <p className="text-xs text-gray-500">Created: {new Date(job.created_at).toLocaleString()}</p>
                </div>
                <div className="flex items-center space-x-2">
                  <Button 
                    size="sm"
                    onClick={() => router.push(`/import/establishments/upload/${job.slug}`)}
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

      <TimeContextSelector unitType="establishments" />
      
      <ImportJobCreator 
        definitionSlug="establishment_for_lu_current_year"
        uploadPath="/import/establishments/upload"
        unitType="Establishments"
        onJobCreated={refreshJobs}
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Establishments">
          <AccordionTrigger>
            What is a Formal Establishment? (With corresponding Legal Unit)
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              This option must be used when your establishment file contain a
              column referring to legal_unit_ids already loaded. This option
              should only be used when your data has ids for both establishments
              and legal units. One establishment needs to connect to one legal
              unit, several establishments can connect to the same legal unit.
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
            What is a Formal Establishments file?
          </AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Formal Establishments file is a CSV file containing the
              establishments with relationship to its legal unit. Ids for both
              columns are required, and cannot contain any null values. Have a
              look at this example CSV file to get an idea of how the file
              should be structured:
            </p>
            <a
              href="/demo/formal_establishments_units_demo.csv"
              download="formal_establishments.example.csv"
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
