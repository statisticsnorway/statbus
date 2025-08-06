"use client";

import React, { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { useRouter } from "next/navigation";
import { AlertCircle, CheckCircle, Database, Upload } from "lucide-react";
import { Progress } from "@/components/ui/progress";
import { Tables } from "@/lib/database.types"; // Import Tables type

// Define types locally or import if available globally
type ImportJob = Tables<"import_job">;

interface ImportJobUploadProps {
  jobSlug: string;
  nextPage: string;
  refreshRelevantCounts: () => Promise<void>;
  job: ImportJob | null; // Receive job as prop, can be null initially
  definition: Tables<"import_definition"> | null; 
}

export function ImportJobUpload({ 
  jobSlug, 
  nextPage, 
  refreshRelevantCounts, 
  job, // Receive job state directly
  definition
}: ImportJobUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  // No context needed here anymore
  const router = useRouter();

  // Parent page is responsible for loading the job.
  // The parent page (e.g., LegalUnitsUploadPage) is responsible
  // for ensuring the job is loaded into the context.

  // Effect to navigate when the job (passed as prop) finishes successfully
  useEffect(() => {
    const handleFinishedJob = async () => {
      if (job?.state === "finished") {
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log(`ImportJobUpload: Job ${job.slug} finished. Refreshing counts and base data before navigating to ${nextPage}.`);
        }
        // refreshRelevantCounts is passed as a prop and should be memoized by the parent.
        // It already includes doRefreshBaseData().
        await refreshRelevantCounts(); 
        router.push(nextPage);
      }
    };

    handleFinishedJob();
    // Add refreshRelevantCounts to the dependency array.
    // Ensure it's memoized in the parent component to avoid unnecessary effect runs.
  }, [job?.state, job?.slug, nextPage, router, refreshRelevantCounts]);

  const handleUpload = useCallback(async (fileToUpload: File) => {
    if (!fileToUpload || !job) return;

    setIsUploading(true);
    setFile(fileToUpload);
    setError(null);
    setUploadProgress(0);

    try {
      const formData = new FormData();
      formData.append("file", fileToUpload);
      formData.append("jobSlug", jobSlug);

      // Use XMLHttpRequest for upload progress tracking
      const xhr = new XMLHttpRequest();
      
      // Track upload progress
      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable) {
          const progress = Math.round((event.loaded / event.total) * 100);
          setUploadProgress(progress);
        }
      };
      
      // Set up promise to handle the response
      const uploadPromise = new Promise<void>((resolve, reject) => {
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            resolve();
          } else {
            try {
              const errorData = JSON.parse(xhr.responseText);
              reject(new Error(errorData.message || "Upload failed"));
            } catch {
              reject(new Error(`Upload failed with status ${xhr.status}`));
            }
          }
        };
        
        xhr.onerror = () => {
          reject(new Error("Network error during upload"));
        };
      });
      
      // Open and send the request
      xhr.open("POST", "/api/import/upload");
      xhr.send(formData);
      
      // Wait for upload to complete
      await uploadPromise;

      await refreshRelevantCounts(); // Refresh counts immediately after upload
      
      // No need for setInterval polling here. 
      // The ImportUnitsContext handles job status updates via SSE.
      // We will use the useEffect above to react to the 'finished' state.

    } catch (err) {
      // Ensure isUploading is reset on error
      setError(
        `Error uploading file: ${err instanceof Error ? err.message : String(err)}`
      );
      setIsUploading(false); // Reset upload state on error
      setUploadProgress(0); // Reset progress
      setFile(null);
    }
    // Don't set isUploading false here on success, wait for job state change
  }, [job, jobSlug, refreshRelevantCounts]); // Add dependencies

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      const selectedFile = e.target.files[0];
      handleUpload(selectedFile);
    }
  };

  // Use job prop for loading state check
  if (!job) {
    // Parent component should handle loading state, but provide a fallback
    return <Spinner message="Waiting for import job data..." />;
  }

  // Determine if upload should be allowed based on job state
  const allowUpload = job.state === "waiting_for_upload";
  const { state, import_completed_pct } = job;

  const statusText: { [key: string]: string } = {
    waiting_for_upload: "Waiting for file upload",
    upload_completed: "Upload complete, preparing data...",
    preparing_data: `Preparing data (${Math.round(import_completed_pct ?? 0)}%)`,
    analysing_data: `Analyzing data (${Math.round(import_completed_pct ?? 0)}%)`,
    waiting_for_review: "Awaiting Review",
    approved: "Approved, Queued for Processing",
    processing_data: `Processing data (${Math.round(import_completed_pct ?? 0)}%)`,
    finished: "Import finished successfully",
    rejected: "Import failed",
  };

  return (
    <div className="space-y-4">
      <div className="border rounded-md p-4">
        <h3 className="font-medium mb-2">
          Import Job Status:{" "}
          <span className={state === 'finished' ? 'text-green-600' : state === 'rejected' ? 'text-red-600' : ''}>
            {statusText[state ?? ''] || `Status: ${state}`}
          </span>
        </h3>
        
        {state === 'waiting_for_upload' && (
          <div className="mt-4">
            {isUploading ? (
              <div className="space-y-2">
                <div className="flex items-center text-blue-600">
                  <Upload className="mr-2 h-4 w-4" />
                  <span>Uploading {file?.name}... ({uploadProgress}%)</span>
                </div>
                <Progress value={uploadProgress} className="h-2" />
              </div>
            ) : (
              <div className="border-2 border-dashed border-gray-300 rounded-md p-4 text-center">
                <input
                  type="file"
                  id="file-upload"
                  accept=".csv"
                  onChange={handleFileChange}
                  className="hidden"
                  disabled={isUploading}
                />
                <label
                  htmlFor="file-upload"
                  className="cursor-pointer flex flex-col items-center justify-center"
                >
                  <Upload className="h-8 w-8 text-gray-400 mb-2" />
                  <span className="text-sm font-medium text-gray-700">
                    Click to select a CSV file
                  </span>
                </label>
              </div>
            )}
          </div>
        )}

        {["upload_completed", "preparing_data", "analysing_data", "processing_data"].includes(state ?? '') && (
          <Progress value={import_completed_pct ?? 0} className="h-2 mt-2" />
        )}
      </div>

      {allowUpload && (
        <div className="border rounded-md p-4">
          <h4 className="font-medium text-gray-800 mb-2">
            Expected File Format
          </h4>
          <div className="text-sm text-gray-700 space-y-2">
            <p>
              Your CSV file should include the following required columns:
            </p>
            <ul className="list-disc pl-5 space-y-1">
              {definition?.mode === "legal_unit" && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (legal unit name)</li>
                  <li>tax_ident (tax identification number)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {definition?.mode === "establishment_formal" && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>legal_unit_id (reference to legal unit)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {definition?.mode === "establishment_informal" && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
            </ul>
            {!job.time_context_ident && (
              <p className="font-medium">
                This import requires valid_from and valid_to date columns in
                ISO format (YYYY-MM-DD).
              </p>
            )}
          </div>
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          {error}
        </div>
      )}

      {/* Show continue button only when job is finished */}
      {/* Use job prop */}
      {job.state === "finished" && (
        <Button onClick={() => router.push(nextPage)} className="w-full mt-4">
          Continue to Next Step
        </Button>
      )}
    </div>
  );
}
