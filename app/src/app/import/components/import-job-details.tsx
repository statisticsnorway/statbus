"use client";

import React from "react";
// import { useImportUnits } from "../import-units-context"; // Removed as it's not used
import { formatDate } from "@/lib/utils";
import { CalendarClock, FileSpreadsheet, Info } from "lucide-react";

import { Tables } from "@/lib/database.types"; // Import Tables type

// Define types locally or import if available globally
type ImportJob = Tables<"import_job">;
type ImportDefinition = Tables<"import_definition">;

interface ImportJobDetailsProps {
  job: ImportJob;
  // Definition might be null if not fetched or related
  definition: ImportDefinition | null; 
}

export function ImportJobDetails({ job, definition }: ImportJobDetailsProps) {
  // No context needed here anymore

  // An import job uses a time context if its `default_valid_from` field is set.
  // This is set by `createImportJobAtom` when a time context is selected in the UI.
  // If it's null, the job expects explicit dates from the CSV file.
  // We check the job object directly, rather than the definition, because we now
  // always use an `_explicit_dates` definition which never has a `time_context_ident`.
  const hasTimeContext = !!job?.default_valid_from;
  
  // Determine import type based on the job's slug
  const getImportType = () => {
    // Use the passed-in job prop
    const slug = definition?.slug; 
    if (!slug) return "Unknown Import Type";
    
    if (slug.includes("legal_unit")) return "Legal Units";
    if (slug.includes("establishment_for_lu")) return "Establishments with Legal Units";
    if (slug.includes("establishment_without_lu"))
      return "Establishments without Legal Units";
    return "Unknown Import Type";
  };
  return (
    <div className="border rounded-md p-4">
      <h3 className="font-medium mb-3">Import Configuration</h3>
      <div className="space-y-1 text-sm">
        <div className="flex justify-between items-center">
          <span className="text-gray-600">Import Type</span>
          <span className="font-medium text-right">{getImportType()}</span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-gray-600">Date Handling</span>
          <span className="font-medium flex items-center gap-1">
            {!hasTimeContext ? (
              <>
                <FileSpreadsheet className="h-4 w-4 text-gray-500" />
                <span>From CSV</span>
              </>
            ) : (
              <>
                <CalendarClock className="h-4 w-4 text-gray-500" />
                <span>Time Context</span>
              </>
            )}
          </span>
        </div>
        {hasTimeContext && (
          <>
            <div className="flex justify-between pl-4">
              <span className="text-gray-600">Valid From</span>
              <span className="font-medium">
                {job?.default_valid_from
                  ? formatDate(new Date(job.default_valid_from))
                  : "N/A"}
              </span>
            </div>
            <div className="flex justify-between pl-4">
              <span className="text-gray-600">Valid To</span>
              <span className="font-medium">
                {job?.default_valid_to
                  ? job.default_valid_to === "infinity"
                    ? "Present"
                    : formatDate(new Date(job.default_valid_to))
                  : "N/A"}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
