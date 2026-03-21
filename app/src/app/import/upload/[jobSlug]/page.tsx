"use client";

import React, { useState, useRef, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { ImportJobUpload } from "../../components/import-job-upload";
import { ImportJobDetails } from "../../components/import-job-details";
import { use } from "react";
import { Spinner } from "@/components/ui/spinner";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import { useSetAtom } from "jotai";
import { refreshBaseDataAtom } from "@/atoms/base-data";

type ImportJob = Tables<"import_job">;
type ImportDefinition = Tables<"import_definition">;

export default function GenericUploadPage({
  params,
}: {
  params: Promise<{ jobSlug: string }>;
}) {
  const doRefreshBaseData = useSetAtom(refreshBaseDataAtom);
  const { jobSlug } = use(params);

  const memoizedRefreshRelevantCounts = useCallback(async () => {
    await doRefreshBaseData();
  }, [doRefreshBaseData]);

  const [job, setJob] = useState<ImportJob | null>(null);
  const [definition, setDefinition] = useState<ImportDefinition | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const eventSourceRef = useRef<EventSource | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useGuardedEffect(() => {
    let isMounted = true;

    async function loadJob() {
      if (!jobSlug) {
        setError("Job slug is missing.");
        setIsLoading(false);
        return;
      }

      setIsLoading(true);
      setError(null);
      setJob(null);
      setDefinition(null);

      try {
        const client = await getBrowserRestClient();
        if (!client) throw new Error("Failed to initialize REST client");

        const { data: jobData, error: jobError } = await client
          .from("import_job")
          .select("*, import_definition(*)")
          .eq("slug", jobSlug)
          .maybeSingle();

        if (jobError) throw jobError;

        if (jobData && isMounted) {
          const fetchedJob = jobData as ImportJob;
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

    return () => {
      isMounted = false;
    };
  }, [jobSlug], 'GenericUploadPage:loadJob');

  useGuardedEffect(() => {
    if (!job?.id) {
      if (eventSourceRef.current) {
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
    const maxReconnectDelay = 30000;

    const connectSSE = () => {
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }

      const newEventSource = new EventSource(`/api/sse/import-jobs?ids=${jobId}&scope=updates_for_ids_only`);
      eventSourceRef.current = newEventSource;

      newEventSource.addEventListener("heartbeat", () => {});

      newEventSource.onmessage = (event) => {
        try {
          if (event.data.trim() === '') return;
          const ssePayload = JSON.parse(event.data);
          if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

          if (!ssePayload || typeof ssePayload !== 'object' || !ssePayload.verb || !ssePayload.import_job) {
            return;
          }

          const verb = ssePayload.verb as 'INSERT' | 'UPDATE' | 'DELETE';
          const jobData = ssePayload.import_job;

          if (jobData.id !== jobId) return;

          if (verb === "DELETE") {
            setJob(null);
            setError("This import job has been deleted.");
            eventSourceRef.current?.close();
            eventSourceRef.current = null;
            return;
          }

          if (verb === 'UPDATE' || verb === 'INSERT') {
            const updatedJobData = jobData as ImportJob;
            setJob(prevJob => prevJob ? { ...prevJob, ...updatedJobData } : updatedJobData);
          }
        } catch (error) {
          console.error("Error parsing SSE message:", error);
        }
      };

      newEventSource.onerror = () => {
        if (newEventSource.readyState === 2) {
          eventSourceRef.current = null;
        } else {
          newEventSource.close();
        }

        reconnectAttempt++;
        const baseDelay = Math.min(1000 * Math.pow(1.5, reconnectAttempt), maxReconnectDelay);
        const jitter = Math.random() * 0.3 * baseDelay;
        const reconnectDelay = Math.floor(baseDelay + jitter);

        reconnectTimeoutRef.current = setTimeout(() => {
          if (job?.id === jobId) {
            connectSSE();
          }
        }, reconnectDelay);
      };
    };

    connectSSE();

    return () => {
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
    };
  }, [job?.id], 'GenericUploadPage:sseListener');

  if (isLoading) {
    return <Spinner message={`Loading import job ${jobSlug}...`} />;
  }

  if (error) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Error: {error}. Please return to the <a href="/import/jobs" className="underline">jobs page</a>.
      </div>
    );
  }

  if (!job) {
    return (
      <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-md text-yellow-800">
        Waiting for import job data... If this persists, the job might not exist.
        Return to the <a href="/import/jobs" className="underline">jobs page</a>.
      </div>
    );
  }

  const heading = definition?.name ?? "Upload Data";

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">{heading}</h1>

      <ImportJobDetails job={job} definition={definition} />

      <ImportJobUpload
        jobSlug={jobSlug}
        job={job}
        definition={definition}
        nextPage="/import/jobs"
        refreshRelevantCounts={memoizedRefreshRelevantCounts}
      />
    </section>
  );
}
