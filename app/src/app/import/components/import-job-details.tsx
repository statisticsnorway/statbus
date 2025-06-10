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

  // Check if the import definition has a time_context_ident - if yes, it uses time context
  // Use the passed-in definition prop
  const hasTimeContext = !!definition?.time_context_ident;
  
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
    <div className="bg-gray-50 border rounded-md p-4 mb-6">
      <h3 className="font-medium mb-3 flex items-center">
        <Info className="h-4 w-4 mr-2 text-blue-500" />
        Import Configuration
      </h3>
      
      <div className="space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-gray-600">Import Type:</span>
          <span className="font-medium">
            {getImportType()}
          </span>
        </div>
        
        <div className="flex justify-between">
          <span className="text-gray-600">Date Format:</span>
          <span className="font-medium flex items-center">
            {!hasTimeContext ? (
              <>
                <FileSpreadsheet className="h-4 w-4 mr-1 text-gray-500" />
                Using explicit dates from CSV
              </>
            ) : (
              <>
                <CalendarClock className="h-4 w-4 mr-1 text-gray-500" />
                Using time context
              </>
            )}
          </span>
        </div>
        
        {hasTimeContext && (
          <>
            <div className="flex justify-between">
              <span className="text-gray-600">Valid From:</span>
              <span className="font-medium">
                {/* Use job prop */}
                {job?.default_valid_from
                  ? formatDate(new Date(job.default_valid_from))
                  : "Not specified"}
              </span>
            </div>

            <div className="flex justify-between">
              <span className="text-gray-600">Valid To:</span>
              <span className="font-medium">
                {/* Use job prop */}
                {job?.default_valid_to
                  ? job.default_valid_to === "infinity"
                    ? "Present (infinity)"
                    : formatDate(new Date(job.default_valid_to))
                  : "Not specified"}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
