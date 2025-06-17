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
  // Definition might not be strictly needed here, but could be useful for format info
  // definition: Tables<"import_definition"> | null; 
}

export function ImportJobUpload({ 
  jobSlug, 
  nextPage, 
  refreshRelevantCounts, 
  job // Receive job state directly
}: ImportJobUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadComplete, setUploadComplete] = useState(false);
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

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setFile(e.target.files[0]);
      setError(null);
    }
  };

  const handleUpload = useCallback(async () => {
    // Use the job prop
    if (!file || !job) return; 

    setIsUploading(true);
    setError(null);
    setUploadProgress(0);

    try {
      const formData = new FormData();
      formData.append("file", file);
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

      setUploadComplete(true); // Indicate upload finished, processing starts
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
      setUploadComplete(false); // Ensure upload complete flag is reset
      setUploadProgress(0); // Reset progress
    }
    // Don't set isUploading false here on success, wait for job state change
  }, [file, job, jobSlug, refreshRelevantCounts]); // Add dependencies

  const getJobStatusDisplay = () => {
    // Use the job prop
    if (!job) return null; 

    const { state, import_completed_pct } = job;

    // Use correct states from Tables<"import_job">["state"]
    switch (state) {
      case "waiting_for_upload":
        return (
          <div className="flex items-center text-gray-600">
            <Upload className="mr-2 h-4 w-4" />
            <span>Waiting for file upload</span>
          </div>
        );
      case "upload_completed":
        return (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center text-blue-600">
                <Database className="mr-2 h-4 w-4" />
                <span>Upload complete, preparing data...</span>
              </div>
              {/* Progress might not be available yet, or could be 0 */}
              <Progress value={import_completed_pct ?? 0} className="h-2" />
            </div>
          </div>
        );
      case "preparing_data":
        return (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center text-blue-600">
                <Database className="mr-2 h-4 w-4" />
                <span>Preparing data ({Math.round(import_completed_pct ?? 0)}%)</span>
              </div>
              <Progress value={import_completed_pct ?? 0} className="h-2" />
            </div>
          </div>
        );
      case "analysing_data":
        return (
          <div className="space-y-2">
            <div className="flex items-center text-blue-600">
              <Spinner className="mr-2 h-4 w-4" />
              <span>Analyzing data ({Math.round(import_completed_pct ?? 0)}%)</span>
            </div>
            <Progress value={import_completed_pct ?? 0} className="h-2" />
          </div>
        );
      case "waiting_for_review":
         return (
          <div className="flex items-center text-blue-600">
            <Spinner className="mr-2 h-4 w-4" />
            <span>Awaiting Review</span>
          </div>
        );
      case "approved":
         return (
          <div className="flex items-center text-blue-600">
            <Spinner className="mr-2 h-4 w-4" />
            <span>Approved, Queued for Processing</span>
          </div>
        );
      case "processing_data":
         return (
          <div className="space-y-2">
            <div className="flex items-center text-blue-600">
              <Spinner className="mr-2 h-4 w-4" />
              <span>Processing data ({Math.round(import_completed_pct ?? 0)}%)</span>
            </div>
            <Progress value={import_completed_pct ?? 0} className="h-2" />
          </div>
        );
      case "finished":
        return (
          <div className="flex items-center text-green-600">
            <CheckCircle className="mr-2 h-4 w-4" />
            <span>Import finished successfully</span>
          </div>
        );
      case "rejected": // Use 'rejected' instead of 'error'
        return (
          <div className="flex items-center text-red-600">
            <AlertCircle className="mr-2 h-4 w-4" />
            <span>Import failed</span>
          </div>
        );
      default:
        return (
          <div className="flex items-center text-gray-600">
            <span>Status: {state}</span>
          </div>
        );
    }
  };

  // Use job prop for loading state check
  if (!job) { 
    // Parent component should handle loading state, but provide a fallback
    return <Spinner message="Waiting for import job data..." />; 
  }

  // Determine if upload should be allowed based on job state
  const allowUpload = job.state === "waiting_for_upload";

  return (
    <div className="space-y-6">
      <div className="border rounded-md p-4">
        <h3 className="font-medium mb-2">Import Job Status</h3>
        {getJobStatusDisplay()}
      </div>

      {/* Only show upload section if job state allows */}
      {allowUpload && (
        <div className="space-y-4">
          {/* File format info based on job type */}
          {/* TODO: Consider passing definition prop if needed for more specific format info */}
          <div className="bg-blue-50 border border-blue-200 rounded-md p-4 text-sm">
            <h4 className="font-medium text-blue-800 mb-2">
              Expected File Format
            </h4>
            <p className="text-blue-700 mb-2">
              Your CSV file should include the following required columns:
            </p>
            <ul className="list-disc pl-5 text-blue-700 mb-2">
              {/* Use job prop */}
              {job.slug?.includes("legal_unit") && ( 
                <>
                  <li>id (unique identifier)</li>
                  <li>name (legal unit name)</li>
                  <li>tax_ident (tax identification number)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {/* Use job prop */}
              {job.slug?.includes("establishment_for_lu") && ( 
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>legal_unit_id (reference to legal unit)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {/* Use job prop */}
              {job.slug?.includes("establishment_without_lu") && ( 
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
            </ul>
            {/* Use job prop */}
            {job.slug?.includes("explicit_dates") && ( 
              <p className="text-blue-700 font-medium">
                This import requires valid_from and valid_to date columns in ISO
                format (YYYY-MM-DD).
              </p>
            )}
          </div>
          
          <div className="border-2 border-dashed border-gray-300 rounded-md p-6 text-center">
            <input
              type="file"
              id="file-upload"
              accept=".csv"
              onChange={handleFileChange}
              className="hidden"
            />
            <label
              htmlFor="file-upload"
              className="cursor-pointer flex flex-col items-center justify-center"
            >
              <Upload className="h-10 w-10 text-gray-400 mb-2" />
              <span className="text-sm font-medium text-gray-700">
                Click to select a CSV file
              </span>
              <span className="text-xs text-gray-500 mt-1">
                or drag and drop
              </span>
            </label>
          </div>

          {file && (
            <div className="bg-gray-50 p-3 rounded-md flex justify-between items-center">
              <span className="text-sm truncate max-w-[70%]">{file.name}</span>
              <Button onClick={handleUpload} disabled={isUploading || !file} size="sm">
                {isUploading && !uploadComplete ? ( // Show spinner only during actual XHR upload
                  <Spinner className="mr-2 h-4 w-4" />
                ) : null}
                {isUploading && !uploadComplete ? "Uploading..." : "Upload"}
              </Button>
            </div>
          )}

          {isUploading && !uploadComplete && (
            <div className="space-y-2">
              <div className="flex items-center text-blue-600">
                <Upload className="mr-2 h-4 w-4" />
                <span>Sending to server ({uploadProgress}%)</span>
              </div>
              <Progress value={uploadProgress} className="h-2" />
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              {error}
            </div>
          )}

          {uploadComplete && (
            <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded">
              File uploaded successfully. Processing data...
            </div>
          )}
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
