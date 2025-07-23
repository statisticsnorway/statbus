"use client";

import React, { useEffect, useState, useRef, useCallback } from "react";
import { ImportJobUpload } from "../../../components/import-job-upload";
import { ImportJobDetails } from "../../../components/import-job-details";
import { useImportManager as useImportUnits, usePendingJobsByMode } from '@/atoms/import';
import { use } from "react";
import { Spinner } from "@/components/ui/spinner";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import { useSetAtom } from "jotai";
import { refreshBaseDataAtom } from "@/atoms/base-data";

type ImportJob = Tables<"import_job">;
type ImportDefinition = Tables<"import_definition">;

export default function EstablishmentsUploadPage({
  params,
}: {
  params: Promise<{ jobSlug:string }>;
}) {
  // Only get refreshUnitCount from context
  const { refreshUnitCount } = useImportUnits(); 
  const { refreshJobs: refreshPendingJobs } = usePendingJobsByMode('establishment_formal');
  const doRefreshBaseData = useSetAtom(refreshBaseDataAtom);
  const { jobSlug } = use(params);

  const memoizedRefreshRelevantCounts = useCallback(async () => {
    await refreshUnitCount('establishmentsWithLegalUnit');
    await refreshPendingJobs();
    await doRefreshBaseData();
  }, [refreshUnitCount, refreshPendingJobs, doRefreshBaseData]);

  // Local state for job, definition, loading, and error
  const [job, setJob] = useState<ImportJob | null>(null);
  const [definition, setDefinition] = useState<ImportDefinition | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const eventSourceRef = useRef<EventSource | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Fetch job data on mount/slug change
  useEffect(() => {
    let isMounted = true; // Flag to prevent state updates on unmounted component
    
    async function loadJob() {
      if (!jobSlug) {
        setError("Job slug is missing.");
        setIsLoading(false);
        return;
      }
      
      setIsLoading(true);
      setError(null);
      setJob(null); // Clear previous job data
      setDefinition(null);

      try {
        const client = await getBrowserRestClient();
        if (!client) throw new Error("Failed to initialize REST client");

        // Fetch job and its related definition
        const { data: jobData, error: jobError } = await client
          .from("import_job")
          .select("*, import_definition(*)") // Fetch definition nested
          .eq("slug", jobSlug)
          .maybeSingle(); // Use maybeSingle to handle not found

        if (jobError) throw jobError;

        if (jobData && isMounted) {
          // Extract job and definition
          const fetchedJob = jobData as ImportJob;
          // Type assertion for nested definition
          const fetchedDefinition = (jobData.import_definition as ImportDefinition) || null; 
          
          setJob(fetchedJob);
          setDefinition(fetchedDefinition);
        } else if (!jobData && isMounted) {
          setError(`Import job with slug "${jobSlug}" not found.`);
        }
      } catch (err) {
        console.error(`Failed to load job ${jobSlug}:`, err);
        if (isMounted) {
          setError(err instanceof Error ? err.message : "An unknown error occurred");
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadJob();
    
    // Cleanup function
    return () => {
      isMounted = false;
    };
  }, [jobSlug]);

  // --- SSE Connection Effect ---
  useEffect(() => {
    // Don't connect until job is loaded and has an ID
    if (!job?.id) {
      // Clean up any existing connection if job becomes null
      if (eventSourceRef.current) {
        console.log(`Closing SSE connection because job ID is missing.`);
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
      return;
    }

    const jobId = job.id;
    let reconnectAttempt = 0;
    const maxReconnectDelay = 30000; // 30 seconds max

    const connectSSE = () => {
      // Clean up existing connection before creating a new one
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }

      console.log(`Creating SSE connection for job ${jobId}`);
      const newEventSource = new EventSource(`/api/sse/import-jobs?ids=${jobId}`);
      eventSourceRef.current = newEventSource;

      newEventSource.addEventListener("heartbeat", (event) => {
        // console.debug("Heartbeat received for job", jobId);
      });

      newEventSource.onmessage = (event) => {
        try {
          if (event.data.trim() === '') return;
          const ssePayload = JSON.parse(event.data);
          if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

          if (!ssePayload || typeof ssePayload !== 'object' || !ssePayload.verb || !ssePayload.import_job) {
            console.error("Invalid SSE payload structure (expected import_job key):", ssePayload);
            return;
          }

          const verb = ssePayload.verb as 'INSERT' | 'UPDATE' | 'DELETE';
          const jobData = ssePayload.import_job;

          // Only process updates for the current job ID
          if (jobData.id !== jobId) return;

          if (verb === "DELETE") {
            console.log(`Job ${jobId} was deleted (SSE)`);
            setJob(null); // Clear local job state
            setError("This import job has been deleted.");
            // Close SSE connection as the job is gone
            eventSourceRef.current?.close();
            eventSourceRef.current = null;
            return;
          }

          if (verb === 'UPDATE' || verb === 'INSERT') {
            console.log(`Received ${verb} event for job ${jobId} (SSE)`);
            const updatedJobData = jobData as ImportJob;
            // Update local job state
            setJob(prevJob => prevJob ? { ...prevJob, ...updatedJobData } : updatedJobData);
          }
        } catch (error) {
          console.error("Error parsing SSE message:", error);
        }
      };

      newEventSource.onerror = (error) => {
        console.error(`SSE connection error for job ${jobId}:`, error);
        if (newEventSource.readyState === 2) { // CLOSED
          eventSourceRef.current = null; // Clear ref if closed
        } else {
          newEventSource.close(); // Ensure it's closed
        }

        // Exponential backoff reconnect logic
        reconnectAttempt++;
        const baseDelay = Math.min(1000 * Math.pow(1.5, reconnectAttempt), maxReconnectDelay);
        const jitter = Math.random() * 0.3 * baseDelay;
        const reconnectDelay = Math.floor(baseDelay + jitter);

        console.log(`Attempting SSE reconnect for job ${jobId} in ${reconnectDelay}ms (attempt ${reconnectAttempt})`);
        reconnectTimeoutRef.current = setTimeout(() => {
          // Check if job still exists before reconnecting
          if (job?.id === jobId) { 
             console.log(`Reconnecting SSE for job ${jobId}...`);
             connectSSE(); // Re-run the connection logic
          } else {
             console.log(`Skipping SSE reconnect for job ${jobId} as it's no longer the current job.`);
          }
        }, reconnectDelay);
      };
    };

    connectSSE(); // Initial connection attempt

    // Cleanup function for when component unmounts or job.id changes
    return () => {
      console.log(`Cleaning up SSE connection for job ${jobId}`);
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
    };
  }, [job?.id]); // Re-run effect if job.id changes

  // --- Render Logic ---
  if (isLoading) {
    return <Spinner message={`Loading import job ${jobSlug}...`} />;
  }

  if (error) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Error: {error}. Please return to the <a href="/import/establishments" className="underline">upload page</a>.
      </div>
    );
  }
  
  if (!job) {
    return (
      <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-md text-yellow-800">
        Waiting for import job data... If this persists, the job might not exist.
        Return to the <a href="/import/establishments" className="underline">upload page</a>.
      </div>
    );
  }

  // Now we have a job, render the details and upload components
  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Establishments</h1>
      <p>
        Upload a CSV file containing establishments with legal units you want to use in your
        analysis.
      </p>

      {/* Pass local job and definition state as props */}
      <ImportJobDetails job={job} definition={definition} />
      
      <ImportJobUpload 
        jobSlug={jobSlug}
        job={job} // Pass local job state
        definition={definition}
        nextPage="/import/establishments-without-legal-unit"
        refreshRelevantCounts={memoizedRefreshRelevantCounts}
      />
    </section>
  );
}
