"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useImportManager, usePendingJobsByMode } from "@/atoms/import";
import { ImportJobCreator } from "../components/import-job-creator";
import { ImportTimeFrameSelector } from "../components/time-frame-selector";
import { Spinner } from "@/components/ui/spinner";
import { getBrowserRestClient } from "@/context/RestClientStore";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { InfoBox } from "@/components/info-box";
import { PendingJobsList } from "../components/pending-jobs-list";
import { ImportDemoFiles } from "../components/import-demo-files";
import { statbusConfig } from '@/lib/statbus-config';

export default function LegalUnitsPage() {
  const { counts } = useImportManager();
  // Use the generalized hook with the specific import mode for legal units
  const { jobs: pendingJobs, loading: isLoading, error, refreshJobs } = usePendingJobsByMode("legal_unit");
  const [isClient, setIsClient] = useState(false);
  const [hasLoadedOnce, setHasLoadedOnce] = useState(false);

  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'UploadLegalUnitsPage:setClient');

  useGuardedEffect(() => {
    if (!isLoading) {
      setHasLoadedOnce(true);
    }
  }, [isLoading], 'UploadLegalUnitsPage:setHasLoadedOnce');

  // Listen for any job updates and refresh the pending list
  useGuardedEffect(() => {
    // We connect after the initial load. If there are jobs, we listen for
    // updates to them. We always listen for new INSERTs.
    if (isLoading) return;

    const jobIds = pendingJobs.map(job => job.id).join(',');
    const eventSource = new EventSource(`/api/sse/import-jobs?ids=${jobIds}&scope=updates_and_all_inserts`);


    eventSource.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

        // Any other message implies a potential change in job status
        if (statbusConfig.debug) {
          console.log('SSE: Received job update, refreshing pending jobs for legal_unit.');
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
  }, [refreshJobs, isLoading, pendingJobs], 'UploadLegalUnitsPage:sseConnector');

  // The useGuardedEffect in usePendingJobsByPattern handles initial fetch.
  // If a manual refresh on mount is still desired for some reason, it can be added here,
  // but typically the hook's internal logic should suffice.
  // useGuardedEffect(() => {
  //   refreshJobs();
  // }, [refreshJobs]); // This might cause a double fetch if the hook also fetches.

  const handleDeleteJob = async (jobId: number) => {
    try {
      const client = await getBrowserRestClient();
      const { error } = await client.from("import_job").delete().eq("id", jobId);
      if (error) {
        throw error;
      }
      refreshJobs(); // Refresh the list after deletion
    } catch (err: unknown) {
      console.error("Failed to delete import job:", err);
      alert(`Error deleting job: ${err instanceof Error ? err.message : String(err)}`);
    }
  };

  if (isLoading && !hasLoadedOnce) {
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

      {!isLoading && pendingJobs.length > 0 && (
        <PendingJobsList
          jobs={pendingJobs}
          onDeleteJob={handleDeleteJob}
          unitTypeTitle="Legal Units"
          unitTypeDescription="legal unit"
          uploadPathPrefix="/import/legal-units/upload"
        />
      )}

      <ImportTimeFrameSelector unitType="legal-units" />
      
      <ImportJobCreator 
        importMode="legal_unit"
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
              format to be processed correctly. Download an example to see the
              structure. The correct example to use depends on the &quot;Time
              frame&quot; chosen above.
            </p>
            <ImportDemoFiles demoFile="legal_units_demo.csv" sourceDatesDemoFile="legal_units_with_source_dates_demo.csv" />
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
