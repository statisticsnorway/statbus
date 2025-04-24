"use client";

import React, { useState, useEffect } from "react";
import { useImportUnits } from "../import-units-context";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { useRouter } from "next/navigation";
import { AlertCircle, CheckCircle, Database, Upload } from "lucide-react";
import { Progress } from "@/components/ui/progress";

interface ImportJobUploadProps {
  jobSlug: string;
  nextPage: string;
  refreshRelevantCounts: () => Promise<void>;
}

export function ImportJobUpload({ jobSlug, nextPage, refreshRelevantCounts }: ImportJobUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadComplete, setUploadComplete] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const { getImportJobBySlug, job, refreshImportJob } = useImportUnits();
  const router = useRouter();

  useEffect(() => {
    const loadJob = async () => {
      await getImportJobBySlug(jobSlug);
    };
    
    loadJob();
    
    // Set up polling for job status
    const interval = setInterval(() => {
      refreshImportJob();
    }, 2000);
    
    return () => clearInterval(interval);
  }, [jobSlug, getImportJobBySlug, refreshImportJob]);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setFile(e.target.files[0]);
      setError(null);
    }
  };

  const handleUpload = async () => {
    if (!file || !job.currentJob) return;

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

      setUploadComplete(true);
      await refreshRelevantCounts();
      
      // Wait for processing to complete
      const checkInterval = setInterval(async () => {
        await refreshImportJob();

        // Use correct states: 'finished' and 'rejected'
        if (job.currentJob?.state === "finished" ||
            job.currentJob?.state === "rejected") {
          clearInterval(checkInterval);

          if (job.currentJob.state === "finished") {
            router.push(nextPage);
          }
        }
      }, 2000);
      
    } catch (err) {
      setError(`Error uploading file: ${err instanceof Error ? err.message : String(err)}`);
      setIsUploading(false);
    }
  };

  const getJobStatusDisplay = () => {
    if (!job.currentJob) return null;
    
    const { state, import_completed_pct } = job.currentJob;
    
    // Use correct states from Tables<"import_job">["state"]
    switch (state) {
      case "waiting_for_upload":
        return (
          <div className="flex items-center text-gray-600">
            <Upload className="mr-2 h-4 w-4" />
            <span>Waiting for file upload</span>
          </div>
        );
      // Assuming 'upload_completed' means server received file, 'preparing_data' is next
      case "upload_completed":
      case "preparing_data":
        return (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center text-blue-600">
                <Database className="mr-2 h-4 w-4" />
                {/* Provide default 0 for Math.round */}
                <span>Preparing data ({Math.round(import_completed_pct ?? 0)}%)</span>
              </div>
              <Progress value={import_completed_pct ?? 0} className="h-2" />
            </div>
          </div>
        );
      // Assuming 'analysing_data' is the state for analysis
      case "analysing_data":
        return (
          <div className="space-y-2">
            <div className="flex items-center text-blue-600">
              <Spinner className="mr-2 h-4 w-4" />
              {/* Provide default 0 for Math.round */}
              <span>Analyzing data ({Math.round(import_completed_pct ?? 0)}%)</span>
            </div>
            <Progress value={import_completed_pct ?? 0} className="h-2" />
          </div>
        );
      // Assuming 'importing_data' is the state for final import step
      case "importing_data":
         return (
          <div className="space-y-2">
            <div className="flex items-center text-blue-600">
              <Spinner className="mr-2 h-4 w-4" />
              {/* Provide default 0 for Math.round */}
              <span>Importing data ({Math.round(import_completed_pct ?? 0)}%)</span>
            </div>
            <Progress value={import_completed_pct ?? 0} className="h-2" />
          </div>
        );
      // Assuming 'waiting_for_review' and 'approved' are intermediate states before 'finished'
      case "waiting_for_review":
      case "approved":
         return (
          <div className="flex items-center text-blue-600">
            <Spinner className="mr-2 h-4 w-4" />
            <span>Finalizing...</span>
          </div>
        );
      case "finished": // Use 'finished' instead of 'completed'
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

  if (!job.currentJob) {
    return <Spinner message="Loading import job..." />;
  }

  return (
    <div className="space-y-6">
      <div className="border rounded-md p-4">
        <h3 className="font-medium mb-2">Import Job Status</h3>
        {getJobStatusDisplay()}
      </div>

      {job.currentJob.state === "waiting_for_upload" && (
        <div className="space-y-4">
          {/* File format info based on job type */}
          <div className="bg-blue-50 border border-blue-200 rounded-md p-4 text-sm">
            <h4 className="font-medium text-blue-800 mb-2">Expected File Format</h4>
            <p className="text-blue-700 mb-2">
              Your CSV file should include the following required columns:
            </p>
            <ul className="list-disc pl-5 text-blue-700 mb-2">
              {job.currentJob.slug.includes("legal_unit") && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (legal unit name)</li>
                  <li>tax_ident (tax identification number)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {job.currentJob.slug.includes("establishment_for_lu") && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>legal_unit_id (reference to legal unit)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
              {job.currentJob.slug.includes("establishment_without_lu") && (
                <>
                  <li>id (unique identifier)</li>
                  <li>name (establishment name)</li>
                  <li>region_code (region code)</li>
                  <li>activity_category_code (primary activity code)</li>
                </>
              )}
            </ul>
            {job.currentJob.slug.includes("explicit_dates") && (
              <p className="text-blue-700 font-medium">
                This import requires valid_from and valid_to date columns in ISO format (YYYY-MM-DD).
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
              <Button
                onClick={handleUpload}
                disabled={isUploading}
                size="sm"
              >
                {isUploading ? <Spinner className="mr-2 h-4 w-4" /> : null}
                Upload
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

      {/* Use correct state 'finished' */}
      {job.currentJob.state === "finished" && (
        <Button onClick={() => router.push(nextPage)} className="w-full">
          Continue to Next Step
        </Button>
      )}
    </div>
  );
}
