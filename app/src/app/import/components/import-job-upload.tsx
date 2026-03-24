"use client";

import React, { useState, useCallback } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { FileSpreadsheet, Upload, X } from "lucide-react";
import { Progress } from "@/components/ui/progress";
import { Tables } from "@/lib/database.types";
import { inspectFile, convertExcelToCsvBlob, type FilePreview } from "@/lib/excel-to-csv";

type ImportJob = Tables<"import_job">;

interface ImportJobUploadProps {
  jobSlug: string;
  nextPage: string;
  refreshRelevantCounts: () => Promise<void>;
  job: ImportJob | null;
  definition: Tables<"import_definition"> | null;
}

type UploadPhase = 'idle' | 'inspecting' | 'previewing' | 'converting' | 'uploading';

export function ImportJobUpload({
  jobSlug,
  nextPage,
  refreshRelevantCounts,
  job,
  definition
}: ImportJobUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<FilePreview | null>(null);
  const [phase, setPhase] = useState<UploadPhase>('idle');
  const [error, setError] = useState<string | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const router = useRouter();

  useGuardedEffect(() => {
    const handleFinishedJob = async () => {
      if (job?.state === "finished") {
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log(`ImportJobUpload: Job ${job.slug} finished. Refreshing counts and base data before navigating to ${nextPage}.`);
        }
        await refreshRelevantCounts();
        router.push(nextPage);
      }
    };

    handleFinishedJob();
  }, [job?.state, job?.slug, nextPage, router, refreshRelevantCounts], 'ImportJobUpload:handleFinishedJob');

  const handleFileSelect = useCallback(async (selectedFile: File) => {
    setFile(selectedFile);
    setError(null);
    setPhase('inspecting');

    try {
      const filePreview = await inspectFile(selectedFile);
      setPreview(filePreview);
      setPhase('previewing');
    } catch (err) {
      setError(`Error reading file: ${err instanceof Error ? err.message : String(err)}`);
      setPhase('idle');
      setFile(null);
    }
  }, []);

  const handleConfirmUpload = useCallback(async () => {
    if (!file || !job || !preview) return;

    setError(null);

    try {
      let uploadFile: File | Blob = file;
      let uploadFileName = file.name;

      // Convert Excel to CSV client-side, reusing cached arrayBuffer from inspectFile
      if (preview.isExcel) {
        setPhase('converting');
        const csvBlob = await convertExcelToCsvBlob(preview.arrayBuffer ?? file);
        uploadFile = csvBlob;
        uploadFileName = file.name.replace(/\.xlsx?$/i, '.csv');
      }

      setPhase('uploading');
      setUploadProgress(0);

      const formData = new FormData();
      formData.append("file", uploadFile, uploadFileName);
      formData.append("jobSlug", jobSlug);

      const xhr = new XMLHttpRequest();

      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable) {
          const progress = Math.round((event.loaded / event.total) * 100);
          setUploadProgress(progress);
        }
      };

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

      xhr.open("POST", "/api/import/upload");
      xhr.send(formData);

      await uploadPromise;
      await refreshRelevantCounts();

    } catch (err) {
      setError(
        `Error uploading file: ${err instanceof Error ? err.message : String(err)}`
      );
      setPhase('previewing');
      setUploadProgress(0);
    }
  }, [file, job, preview, jobSlug, refreshRelevantCounts]);

  const handleCancel = useCallback(() => {
    setFile(null);
    setPreview(null);
    setPhase('idle');
    setError(null);
    setUploadProgress(0);
  }, []);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      handleFileSelect(e.target.files[0]);
    }
  };

  if (!job) {
    return <Spinner message="Waiting for import job data..." />;
  }

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

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
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
            {phase === 'idle' && (
              <div className="border-2 border-dashed border-gray-300 rounded-md p-4 text-center">
                <input
                  type="file"
                  id="file-upload"
                  accept=".csv,.xlsx"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <label
                  htmlFor="file-upload"
                  className="cursor-pointer flex flex-col items-center justify-center"
                >
                  <Upload className="h-8 w-8 text-gray-400 mb-2" />
                  <span className="text-sm font-medium text-gray-700">
                    Click to select a CSV or Excel file
                  </span>
                </label>
              </div>
            )}

            {phase === 'inspecting' && (
              <div className="flex items-center gap-2 text-sm text-gray-600">
                <Spinner />
                <span>Reading file...</span>
              </div>
            )}

            {phase === 'previewing' && preview && (
              <div className="space-y-3">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-2">
                    <FileSpreadsheet className="h-5 w-5 text-blue-600" />
                    <div>
                      <p className="font-medium text-sm">{preview.fileName}</p>
                      <p className="text-xs text-gray-500">
                        {formatSize(preview.fileSize)}
                        {preview.isExcel ? ' (Excel)' : ' (CSV)'}
                        {' \u00b7 '}~{preview.rowCount.toLocaleString()} rows
                        {' \u00b7 '}{preview.columnNames.length} columns
                      </p>
                    </div>
                  </div>
                  <button onClick={handleCancel} className="text-gray-400 hover:text-gray-600">
                    <X className="h-4 w-4" />
                  </button>
                </div>

                {/* Column names */}
                <div className="text-xs text-gray-600">
                  <span className="font-medium">Columns: </span>
                  {preview.columnNames.join(', ')}
                </div>

                {/* Sample data table */}
                {preview.sampleRows.length > 0 && (
                  <div className="overflow-x-auto max-h-40 border rounded text-xs">
                    <table className="min-w-full">
                      <thead className="bg-gray-50 sticky top-0">
                        <tr>
                          {preview.columnNames.map((col, i) => (
                            <th key={i} className="px-2 py-1 text-left font-medium text-gray-500 whitespace-nowrap">
                              {col}
                            </th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {preview.sampleRows.map((row, ri) => (
                          <tr key={ri} className="border-t">
                            {row.map((cell, ci) => (
                              <td key={ci} className="px-2 py-1 text-gray-700 whitespace-nowrap max-w-[200px] truncate">
                                {cell}
                              </td>
                            ))}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                {preview.isExcel && (
                  <p className="text-xs text-blue-600">
                    Excel file will be converted to CSV before upload.
                  </p>
                )}

                <div className="flex gap-2">
                  <Button onClick={handleConfirmUpload} className="flex-1">
                    <Upload className="mr-2 h-4 w-4" />
                    Upload {preview.isExcel ? '(Convert & Upload)' : ''}
                  </Button>
                  <Button variant="outline" onClick={handleCancel}>
                    Cancel
                  </Button>
                </div>
              </div>
            )}

            {phase === 'converting' && (
              <div className="space-y-2">
                <div className="flex items-center text-blue-600 text-sm">
                  <FileSpreadsheet className="mr-2 h-4 w-4" />
                  <span>Converting Excel to CSV...</span>
                </div>
                <Progress className="h-2" />
              </div>
            )}

            {phase === 'uploading' && (
              <div className="space-y-2">
                <div className="flex items-center text-blue-600 text-sm">
                  <Upload className="mr-2 h-4 w-4" />
                  <span>Uploading {file?.name}... ({uploadProgress}%)</span>
                </div>
                <Progress value={uploadProgress} className="h-2" />
              </div>
            )}
          </div>
        )}

        {["upload_completed", "preparing_data", "analysing_data", "processing_data"].includes(state ?? '') && (
          <div className="mt-2 space-y-2">
            <Progress value={import_completed_pct ?? 0} className="h-2" />
            <a href={`/import/jobs/${job.slug}/data`} className="text-sm text-blue-600 hover:text-blue-800 hover:underline">
              View Data →
            </a>
          </div>
        )}

        {state === 'waiting_for_review' && job?.slug && (
          <div className="mt-4">
            <Button asChild className="bg-blue-600 hover:bg-blue-700 text-white">
              <a href={`/import/jobs/${job.slug}/data`}>Review Data</a>
            </Button>
          </div>
        )}
      </div>

      {allowUpload && phase === 'idle' && (
        <div className="border rounded-md p-4">
          <h4 className="font-medium text-gray-800 mb-2">
            Expected File Format
          </h4>
          <div className="text-sm text-gray-700 space-y-2">
            <p>
              Your CSV or Excel file should include the following required columns:
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

      {job.state === "finished" && (
        <Button onClick={() => router.push(nextPage)} className="w-full mt-4">
          Continue to Next Step
        </Button>
      )}
    </div>
  );
}
