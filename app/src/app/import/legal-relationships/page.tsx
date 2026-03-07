"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { useImportManager, usePendingJobsByMode } from "@/atoms/import";
import { ImportJobCreator } from "../components/import-job-creator";
import { TimeContextSelector } from "../components/time-context-selector";
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

export default function LegalRelationshipsPage() {
  const router = useRouter();
  const { counts, importState } = useImportManager();
  const { selectedDefinition } = importState;
  const { jobs: pendingJobs, loading: isLoading, error, refreshJobs } = usePendingJobsByMode("legal_relationship");
  const [isClient, setIsClient] = useState(false);
  const [hasLoadedOnce, setHasLoadedOnce] = useState(false);

  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'LegalRelationshipsPage:setClient');

  useGuardedEffect(() => {
    if (!isLoading) {
      setHasLoadedOnce(true);
    }
  }, [isLoading], 'LegalRelationshipsPage:setHasLoadedOnce');

  useGuardedEffect(() => {
    if (isLoading) return;

    const jobIds = pendingJobs.map(job => job.id).join(',');
    const eventSource = new EventSource(`/api/sse/import-jobs?ids=${jobIds}&scope=updates_and_all_inserts`);

    eventSource.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

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
  }, [refreshJobs, isLoading, pendingJobs], 'LegalRelationshipsPage:sseConnector');

  const handleDeleteJob = async (jobId: number) => {
    try {
      const client = await getBrowserRestClient();
      const { error } = await client.from("import_job").delete().eq("id", jobId);
      if (error) {
        throw error;
      }
      refreshJobs();
    } catch (err: any) {
      console.error("Failed to delete import job:", err);
      alert(`Error deleting job: ${err.message}`);
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
      <h1 className="text-center text-2xl">Upload Legal Relationships</h1>
      <p>
        Upload a CSV file containing Legal Relationships (ownership links between
        Legal Units) to define Power Groups.
      </p>

      {!isLoading && pendingJobs.length > 0 && (
        <PendingJobsList
          jobs={pendingJobs}
          onDeleteJob={handleDeleteJob}
          unitTypeTitle="Legal Relationships"
          unitTypeDescription="legal relationship"
          uploadPathPrefix="/import/legal-relationships/upload"
        />
      )}

      <TimeContextSelector unitType="legal-relationships" />

      <ImportJobCreator
        importMode="legal_relationship"
        uploadPath="/import/legal-relationships/upload"
        unitType="Legal Relationships"
        onJobCreated={refreshJobs}
      />

      <Accordion type="single" collapsible>
        <AccordionItem value="Legal Relationship">
          <AccordionTrigger>What is a Legal Relationship?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A <strong>Legal Relationship</strong> represents a control or
              ownership link between two Legal Units. Relationship types marked
              as hierarchy-forming (e.g. control) define{" "}
              <strong>Power Groups</strong> — clusters of entities under common
              control. Other types (e.g. ownership) record shared stakes without
              affecting the hierarchy.
            </p>
          </AccordionContent>
        </AccordionItem>
        <AccordionItem value="Legal Relationships File">
          <AccordionTrigger>What is a Legal Relationships file?</AccordionTrigger>
          <AccordionContent>
            <p className="mb-3">
              A Legal Relationships file is a CSV file containing relationship
              links. Each row specifies an influencing Legal Unit, an influenced
              Legal Unit, a relationship type code, and an optional percentage.
            </p>
            <div className="flex flex-col space-y-2 pl-4">
              <a
                href="/demo/legal_relationships_demo.csv"
                download="legal_relationships_demo.csv"
                className={`underline ${
                  selectedDefinition?.valid_time_from === "job_provided"
                    ? "font-bold"
                    : ""
                }`}
              >
                Example for jobs with a defined validity period
              </a>
              <a
                href="/demo/legal_relationships_with_source_dates_demo.csv"
                download="legal_relationships_with_source_dates_demo.csv"
                className={`underline ${
                  selectedDefinition?.valid_time_from === "source_columns"
                    ? "font-bold"
                    : ""
                }`}
              >
                Example for jobs with validity from source file (valid_from,
                valid_to)
              </a>
            </div>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </section>
  );
}
