"use client";

import React, { useEffect, useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { formatDistanceToNow } from "date-fns";
import { Database, Tables } from '@/lib/database.types'; // Import Tables

// Use the generated type for ImportJob
type ImportJob = Tables<"import_job">;

export default function ImportJobsPage() {
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [eventSource, setEventSource] = useState<EventSource | null>(null);

  useEffect(() => {
    const fetchJobs = async () => {
      try {
        setLoading(true);
        const client = await getBrowserRestClient();
        // Select all columns from import_job table
        const { data: fetchedData, error } = await client
          .from("import_job")
          .select("*")
          .order("created_at", { ascending: false });

        if (error || !fetchedData) { // Check for error or null data
           throw new Error(error?.message || "Failed to fetch jobs: No data returned");
        }

        // Data is confirmed to be an array of objects here
        // Type assertion might be needed if TS still complains
        const jobsData: ImportJob[] = fetchedData;
        setJobs(jobsData);
      } catch (err) {
        setError(`Failed to load import jobs: ${err instanceof Error ? err.message : String(err)}`);
      } finally {
        setLoading(false);
      }
    };

    fetchJobs();
  }, []);

  useEffect(() => {
    if (jobs.length === 0) return;

    // Get active job IDs (those not in completed or error state)
    const activeJobIds = jobs
      .filter(job => !["completed", "error"].includes(job.state))
      .map(job => job.id);

    if (activeJobIds.length === 0) return;

    // Create SSE connection for active jobs
    const source = new EventSource(`/api/sse/import-jobs?ids=${activeJobIds.join(',')}`);

    source.onmessage = (event) => {
      try {
        // Assuming SSE payload contains partial updates matching ImportJob fields
        const ssePayload = JSON.parse(event.data);
        const updatedJobData = ssePayload as Partial<ImportJob> & { id: number };

        setJobs(prevJobs =>
          prevJobs.map(job =>
            job.id === updatedJobData.id
              ? // Safer merge + Explicit Cast: Ensure all original fields are kept unless explicitly updated by SSE
                ({
                  ...job, // Start with the original job
                  ...updatedJobData, // Overwrite with fields present in the SSE data
                } as ImportJob) // Cast the result back to ImportJob
              : job
          )
        );
      } catch (error) {
        console.error("Error parsing SSE message:", error);
      }
    };

    source.onerror = () => {
      source.close();
    };

    setEventSource(source);

    return () => {
      source.close();
    };
  }, [jobs]);

  const getStateBadge = (state: string) => {
    switch (state) {
      case "waiting_for_upload":
        return <Badge variant="outline">Waiting</Badge>;
      case "uploading":
        return <Badge variant="secondary">Uploading</Badge>;
      case "processing":
        return <Badge variant="secondary">Processing</Badge>;
      case "analyzing":
        return <Badge variant="secondary">Analyzing</Badge>;
      case "completed":
        return <Badge className="bg-green-500 text-white">Completed</Badge>;
      case "error":
        return <Badge variant="destructive">Error</Badge>;
      default:
        return <Badge>{state}</Badge>;
    }
  };

  if (loading) {
    return <Spinner message="Loading import jobs..." />;
  }

  if (error) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        {error}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold">Import Jobs</h1>
      
      {jobs.length === 0 ? (
        <p className="text-gray-500">No import jobs found.</p>
      ) : (
        <div className="border rounded-md">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Description</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Progress</TableHead>
                <TableHead>Created</TableHead>
                <TableHead>Last Updated</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {jobs.map((job) => (
                <TableRow key={job.id}>
                  <TableCell className="font-medium">{job.description}</TableCell>
                  <TableCell>{getStateBadge(job.state)}</TableCell>
                  <TableCell>
                    {/* Use correct states that indicate progress */}
                    {["upload_completed", "preparing_data", "analysing_data", "importing_data"].includes(job.state) ? (
                      <div className="w-32">
                         {/* Provide default 0 for value and Math.round */}
                        <Progress value={job.import_completed_pct ?? 0} className="h-2" />
                        <span className="text-xs text-gray-500">{Math.round(job.import_completed_pct ?? 0)}%</span>
                      </div>
                    ) : job.state === "finished" ? ( // Use correct state 'finished'
                      <span className="text-xs text-green-600">100%</span>
                    ) : null}
                  </TableCell>
                  <TableCell className="text-sm text-gray-500">
                    {formatDistanceToNow(new Date(job.created_at), { addSuffix: true })}
                  </TableCell>
                  <TableCell className="text-sm text-gray-500">
                    {formatDistanceToNow(new Date(job.updated_at), { addSuffix: true })}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
