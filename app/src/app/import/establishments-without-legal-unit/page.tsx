"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import React, { useEffect, useState } from "react"; // Removed useState
import { InfoBox } from "@/components/info-box";
import { useImportManager, usePendingJobsByMode } from "@/atoms/import"; // Updated import
import { TimeContextSelector } from "../components/time-context-selector";
import { ImportJobCreator } from "../components/import-job-creator";
import { Spinner } from "@/components/ui/spinner";
import { Button } from "@/components/ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import { useRouter } from "next/navigation";
import { PendingJobsList } from "../components/pending-jobs-list";

export default function UploadEstablishmentsWithoutLegalUnitPage() {
  const router = useRouter();
  const { counts: { establishmentsWithoutLegalUnit } } = useImportManager();
  // Use the generalized hook with the specific import mode for informal establishments
  const { jobs: pendingJobs, loading: isLoading, error, refreshJobs } = usePendingJobsByMode("establishment_informal");
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  // Listen for any job updates and refresh the pending list
  useEffect(() => {
    const eventSource = new EventSource('/api/sse/import-jobs');

    eventSource.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

        // Any other message implies a potential change in job status
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log('SSE: Received job update, refreshing pending jobs for establishment_informal.');
        }
        refreshJobs();
      } catch (e) {
        console.error("Failed to parse SSE message on pending jobs page:", e);
      }
    };

    eventSource.onerror = (error) => {
      console.error('SSE error on pending jobs page:', error);
      eventSource.close();
    };

    return () => {
      eventSource.close();
    };
  }, [refreshJobs]);

  // The useEffect in usePendingJobsByPattern handles initial fetch.

  const handleDeleteJob = async (jobId: number) => {
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
  };

  if (isLoading && pendingJobs.length === 0) {
    return <Spinner message="Checking for existing import jobs..." />;
  }

  if (error) {
    return <InfoBox variant="error"><p>Error loading pending jobs: {error}</p></InfoBox>;
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

      {isClient && !!establishmentsWithoutLegalUnit &&
        establishmentsWithoutLegalUnit > 0 && (
          <InfoBox>
            <p>
              There are already {establishmentsWithoutLegalUnit}{" "}
              informal establishments defined
            </p>
          </InfoBox>
        )}

      <PendingJobsList
        jobs={pendingJobs}
        onDeleteJob={handleDeleteJob}
        unitTypeTitle="Establishments Without Legal Unit"
        unitTypeDescription="establishment without legal unit"
        uploadPathPrefix="/import/establishments-without-legal-unit/upload"
      />

      <TimeContextSelector unitType="establishments-without-legal-unit" />
      
      <ImportJobCreator 
        importMode="establishment_informal"
        uploadPath="/import/establishments-without-legal-unit/upload"
        unitType="Establishments Without Legal Unit"
        onJobCreated={refreshJobs}
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
