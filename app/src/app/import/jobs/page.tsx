"use client";

export const dynamic = 'force-dynamic'; // Ensure this page is dynamically rendered

import React, { useEffect, useState, useRef } from "react"; // Add useRef
import useSWR, { useSWRConfig } from 'swr'; // Import useSWR and useSWRConfig for mutate
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { 
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
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
import { AlertCircle } from "lucide-react"; // Import AlertCircle
import { Database, Tables } from '@/lib/database.types';

// Use the generated type for ImportJob
type ImportJob = Tables<"import_job">;

// --- SWR Key Definitions ---
// Key for the list of all import jobs
const SWR_KEY_IMPORT_JOBS = "/api/import-jobs"; 
// Function to generate a key for a single import job
const getJobSWRKey = (id: number | string) => `/api/import-jobs/${id}`;

// --- Fetcher Function (assuming one exists or define it) ---
// Example fetcher using the browser client
// Simplified to always return Promise<ImportJob[]>
const fetcher = async (key: string): Promise<ImportJob[]> => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available");

  const listMatch = key.match(/^\/api\/import-jobs\/?$/);
  const singleMatch = key.match(/^\/api\/import-jobs\/([^/]+)$/);

  if (listMatch) {
    // Fetching list of all jobs
    const { data, error } = await client
      .from("import_job")
      .select("*, import_definition:import_definition_id(slug, name, description)")
      .order("created_at", { ascending: false }); // Default sort for list view
    if (error) {
      console.error("SWR Fetcher error (list jobs):", error);
      throw error;
    }
    // Assuming ImportJob type can accommodate the nested import_definition
    return data as ImportJob[];
  } else if (singleMatch) {
    // Fetching a single job
    const jobIdOrSlug = singleMatch[1];
    // Determine if jobIdOrSlug is numeric (ID) or string (slug)
    const columnToFilter = /^\d+$/.test(jobIdOrSlug) ? "id" : "slug";
    const valueToFilter = columnToFilter === "id" ? parseInt(jobIdOrSlug, 10) : jobIdOrSlug;

    const { data, error } = await client
      .from("import_job")
      .select("*, import_definition:import_definition_id(slug, name, description)")
      .eq(columnToFilter, valueToFilter)
      .maybeSingle();
    if (error) {
      console.error(`SWR Fetcher error (single job ${jobIdOrSlug}):`, error);
      throw error;
    }
    // Return as an array (list of 0 or 1 item)
    return data ? [data as ImportJob] : [];
  } else {
    console.error(`SWR Fetcher error: Unrecognized key pattern: ${key}`);
    throw new Error(`Unrecognized SWR key pattern: ${key}`);
  }
};
// --- Component ---
export default function ImportJobsPage() {
  // Use SWR for data fetching, loading, and error state
  const { data: jobs = [], error: swrError, isLoading } = useSWR<ImportJob[], Error>(
    SWR_KEY_IMPORT_JOBS,
    fetcher,
    {
      // Optional: Configure SWR options like refreshInterval, revalidateOnFocus, etc.
      // refreshInterval: 5000, // Example: Refresh every 5 seconds (use cautiously)
      // refreshInterval: 30000, // Example: Refresh every 30 seconds
      revalidateOnFocus: false, // Optional: Disable revalidation on window focus
    }
  );
  const { mutate } = useSWRConfig(); // Get mutate function from config
  
  // State to manage the error message displayed in the dialog
  const [errorToShow, setErrorToShow] = useState<string | null>(null);

  // Use a ref to hold the EventSource instance to avoid re-render cycles
  const eventSourceRef = useRef<EventSource | null>(null);
  // Use a ref to track if an SSE connection attempt is in progress or established
  const sseStatusRef = useRef<'idle' | 'connecting' | 'connected' | 'error'>('idle');

  // Store job IDs in a ref to avoid dependency cycles
  const jobIdsRef = React.useRef<number[]>([]);
 
  // Update job IDs ref when jobs change
  useEffect(() => {
    // Get all job IDs for tracking
    const allJobIds = (jobs ?? []) // Handle initial undefined state from SWR
      .filter(job => job.id) // Ensure job.id is not null/undefined
      .map(job => job.id)
      .sort((a, b) => a - b); // Sort numerically
   
    // Update the ref with the new value if it changed
    if (jobIdsRef.current.join(',') !== allJobIds.join(',')) {
      jobIdsRef.current = allJobIds;
    }
  }, [jobs]); // Only depend on jobs
 
  // Manage SSE connection lifecycle
  useEffect(() => {
    // Only run this effect once loading is complete
    if (isLoading) { // Use SWR's isLoading state
      return;
    }

    // Only attempt connection if idle or in error state
    if (sseStatusRef.current !== 'idle' && sseStatusRef.current !== 'error') {
      console.log(`SSE connection attempt skipped, status: ${sseStatusRef.current}`);
      return;
    }

    sseStatusRef.current = 'connecting';
    console.log("Attempting to establish SSE connection...");

    // --- SSE Connection Setup ---
    // We connect without specific IDs now, relying on the server to send relevant updates.
    // The server-side logic might need adjustment if it strictly filters by initial IDs.
    // Connect to the general import jobs SSE endpoint.
    // Assumes the backend will broadcast relevant job updates to all connected clients.
    const sseUrl = `/api/sse/import-jobs`;
      
    console.log(`Creating new SSE connection: ${sseUrl}`);
    const source = new EventSource(sseUrl);

    // Add specific handler for heartbeat events
    source.addEventListener("heartbeat", (event) => {
      // Just log heartbeat at debug level if needed
      // console.debug("Heartbeat received:", event.data);
    });

    source.onmessage = (event) => {
      try {
        // Skip empty messages
        if (event.data.trim() === '') {
          return;
        }
        
        // Parse and validate SSE payload
        const ssePayload = JSON.parse(event.data);
        
        // Skip connection_established messages
        if (ssePayload.type === "connection_established") {
          console.log("SSE connection established:", ssePayload);
          return;
        }
        
        // Skip heartbeat messages
        if (event.type === "heartbeat") {
          return;
        }
        
        console.log("SSE message received (import_job format):", ssePayload);

        // Validate the basic structure { verb: '...', import_job: { ... } }
        if (!ssePayload || typeof ssePayload !== 'object' || !ssePayload.verb || !ssePayload.import_job) {
          console.error("Invalid SSE payload structure (expected import_job key):", ssePayload);
          return;
        }

        const verb = ssePayload.verb as 'INSERT' | 'UPDATE' | 'DELETE';
        const jobData = ssePayload.import_job; // Use the 'import_job' key

        // Handle DELETE
        if (verb === "DELETE") {
          if (!jobData.id || typeof jobData.id !== 'number') {
            console.error("Invalid DELETE notification data:", jobData);
            return;
          }
          const deletedJobId = jobData.id;
          console.log("Processing DELETE for job via SWR mutate:", deletedJobId);

          // Mutate the list: Remove the job
          mutate(SWR_KEY_IMPORT_JOBS, (currentData: ImportJob[] | undefined): ImportJob[] => {
            return (currentData ?? []).filter(job => job.id !== deletedJobId);
          }, { revalidate: false }); // Optimistic update for the list

          // Mutate the individual job: Set data to an empty array to indicate deletion/not found
          mutate(getJobSWRKey(deletedJobId), [], { revalidate: false });

          return; // Exit after handling delete
        }

        // Handle INSERT/UPDATE - jobData should be the full ImportJob object
        const updatedJobData = jobData as ImportJob; // Cast import_job part to ImportJob

        // Validate required fields in the job data
        if (!updatedJobData.id || typeof updatedJobData.id !== 'number') {
          console.error("Invalid job data received (missing id):", updatedJobData);
          return;
        }

        const jobId = updatedJobData.id;
        console.log(`Processing ${verb} for job ${jobId}`, updatedJobData);

        // --- Mutate Individual Job Cache ---
        // Update the specific job's cache first. Pass the full new data as an array.
        mutate(getJobSWRKey(jobId), [updatedJobData], { revalidate: false });

        // --- Mutate List Cache ---
        mutate(SWR_KEY_IMPORT_JOBS, (currentData: ImportJob[] | undefined): ImportJob[] => {
          const currentJobs = currentData ?? [];
          const jobIndex = currentJobs.findIndex(job => job.id === jobId);

          if (verb === 'UPDATE') {
            if (jobIndex !== -1) {
              // Update existing job in the list
              const updatedList = [...currentJobs];
              updatedList[jobIndex] = updatedJobData; // Use the job data directly
              return updatedList;
            } else {
              // Job wasn't in the list, maybe it was created just now? Add it.
              console.warn(`Received UPDATE for job ${jobId} not found in list, adding.`);
              return [updatedJobData, ...currentJobs]; // Add to beginning
            }
          } else { // INSERT
            if (jobIndex === -1) {
              // Add the new job to the list at the end
              return [...currentJobs, updatedJobData];
            } else {
              // Job already exists? This shouldn't happen for INSERT, maybe log or just update.
              console.warn(`Received INSERT for job ${jobId} that already exists in list, updating.`);
              const updatedList = [...currentJobs];
              updatedList[jobIndex] = updatedJobData;
              return updatedList;
            }
          }
        }, { revalidate: false }); // Don't re-fetch immediately after optimistic update

      } catch (error) {
        console.error("Error processing SSE message:", error);
      }
    };

    // Add error handling with exponential backoff
    let reconnectAttempt = 0;
    const maxReconnectDelay = 30000; // 30 seconds max
    
    let reconnectTimeout: NodeJS.Timeout | null = null;
    
    source.onerror = (error) => {
      console.error("SSE connection error:", error);
        
      // Only close if not already closed
      if (source.readyState !== 2) { // 2 = CLOSED
        source.close();
      }
      
      // Calculate backoff delay with exponential increase and jitter
      reconnectAttempt++;
      const baseDelay = Math.min(1000 * Math.pow(1.5, reconnectAttempt), maxReconnectDelay);
      const jitter = Math.random() * 0.3 * baseDelay; // Add up to 30% jitter
      const reconnectDelay = Math.floor(baseDelay + jitter);
      
      console.log(`Attempting to reconnect SSE in ${reconnectDelay}ms (attempt ${reconnectAttempt})`);

      // Clear any existing timeout
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }

      // Attempt to reconnect after calculated delay
      reconnectTimeout = setTimeout(() => {
        console.log("Attempting to reconnect SSE now...");
        reconnectTimeout = null;
        // The SSE connection logic will re-initiate connection if source.onerror is called
        // and the main useEffect re-runs due to its dependencies (e.g., isLoading changing)
        // or if we manually re-trigger the effect by changing a dependency.
        // For now, the existing logic will attempt to reconnect when source.onerror is hit
        // and the effect re-runs. The setSseReconnectTrigger was an explicit way to force this.
        // We can rely on the natural re-run or SWR's own mechanisms if isLoading changes.
        // If a more direct re-trigger is needed, a different state/ref could be used.
        // For now, removing the direct call to setSseReconnectTrigger.
        // The original effect structure will handle re-connection attempts.
        // The main useEffect will re-run if isLoading changes, or if other dependencies were added.
        // The current structure of the useEffect for SSE connection is self-contained for retries.
      }, reconnectDelay);
    };

    // Store the source in the ref
    eventSourceRef.current = source;
    sseStatusRef.current = 'connected'; // Mark as connected
    console.log("SSE connection established and stored in ref.");

    // Cleanup function
    return () => {
      console.log("Cleaning up SSE connection effect...");
      if (eventSourceRef.current) {
        console.log("Closing existing SSE connection.");
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
      sseStatusRef.current = 'idle'; // Reset status on cleanup

      // Clear any pending reconnect timeout
      if (reconnectTimeout) {
        console.log("Clearing pending reconnect timeout.");
        clearTimeout(reconnectTimeout);
      }
    };
  // This effect should run primarily when loading finishes.
  // It manages the connection lifecycle internally using refs.
  }, [isLoading, mutate]); // Add mutate to dependencies

  // Use the actual type for state from the database schema
  const getStateBadge = (state: Tables<"import_job">["state"] | null | undefined) => {
    // Handle null or undefined state gracefully
    if (!state) {
      return <Badge variant="outline">Unknown</Badge>;
    }
    // Align with states used in ImportJobUpload and likely schema
    switch (state) {
      case "waiting_for_upload":
        return <Badge variant="outline">Waiting for Upload</Badge>;
      // Add states corresponding to upload/processing phases if needed, matching ImportJobUpload
      case "upload_completed":
      case "preparing_data":
        return <Badge variant="secondary">Preparing</Badge>;
      case "analysing_data": // Use schema spelling
        return <Badge variant="secondary">Analyzing</Badge>;
      case "processing_data": // Use schema spelling for processing
        return <Badge variant="secondary">Processing</Badge>;
      case "waiting_for_review":
        return <Badge variant="secondary">Review</Badge>;
      case "approved":
         return <Badge variant="secondary">Approved</Badge>;
      case "finished": // Use 'finished' from schema/ImportJobUpload
        return <Badge className="bg-green-600 text-white">Finished</Badge>;
      case "rejected": // Use 'rejected' from schema/ImportJobUpload
        return <Badge variant="destructive">Rejected</Badge>;
      default:
        // Display any other unexpected state directly
        return <Badge variant="outline">{state}</Badge>;
    }
  };
 
  if (isLoading) { // Use SWR's isLoading
    return <Spinner message="Loading import jobs..." />;
  }
 
  if (swrError) { // Use SWR's error
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Failed to load import jobs: {swrError.message}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold">Import Jobs</h1>
       
      {!jobs || jobs.length === 0 ? ( // Handle initial undefined state from SWR
        <p className="text-gray-500">No import jobs found.</p>
      ) : (
        <div className="border rounded-md">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Description</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Progress</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {jobs.map((job) => {
                return (
                <TableRow key={job.id}>
                  <TableCell className="font-medium">{job.description}</TableCell>
                  <TableCell>
                    <div className="flex flex-col space-y-1">
                      <div className="flex items-center space-x-2">
                        {getStateBadge(job.state)}
                        {/* Error Trigger */}
                        {job.error && (
                          <Dialog>
                            <DialogTrigger asChild>
                              <button 
                                onClick={() => setErrorToShow(job.error)} 
                                className="text-red-500 hover:text-red-700"
                                title="Show error details"
                              >
                                <AlertCircle className="h-4 w-4" />
                              </button>
                            </DialogTrigger>
                            {/* DialogContent is rendered outside the table later */}
                          </Dialog>
                        )}
                      </div>
                      {/* Timestamps */}
                      <div className="text-xs text-gray-500">
                        Created: {formatDistanceToNow(new Date(job.created_at), { addSuffix: true })}
                      </div>
                      <div className="text-xs text-gray-500">
                        Updated: {formatDistanceToNow(new Date(job.updated_at), { addSuffix: true })}
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    {/* Show progress for states that have it - align with schema/ImportJobUpload */}
                    {job.state && ["preparing_data", "analysing_data", "processing_data"].includes(job.state) && job.import_completed_pct !== null ? (
                      <div className="w-32">
                        <Progress value={job.import_completed_pct ?? 0} className="h-2" />
                        <span className="text-xs text-gray-500">{Math.round(job.import_completed_pct ?? 0)}%</span>
                      </div>
                    ) : job.state === "finished" ? ( // Use 'finished' state
                      <span className="text-xs text-green-600">100%</span>
                    ) : (
                      // Show dash or empty for states without progress (e.g., waiting, rejected)
                      <span className="text-xs text-gray-400">-</span>
                    )}
                  </TableCell>
                </TableRow>
              )})}
            </TableBody>
          </Table>
        </div>
      )}
      
      {/* Error Dialog */}
      <Dialog open={!!errorToShow} onOpenChange={(open) => !open && setErrorToShow(null)}>
        <DialogContent className="sm:max-w-[600px]">
          <DialogHeader>
            <DialogTitle>Import Job Error</DialogTitle>
            <DialogDescription>
              The following error occurred during the import process.
            </DialogDescription>
          </DialogHeader>
          <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-md text-sm text-red-800 overflow-auto max-h-[60vh]">
            <pre className="whitespace-pre-wrap break-words">{errorToShow}</pre>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
