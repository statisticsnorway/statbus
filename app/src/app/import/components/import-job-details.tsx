"use client";

import React from "react";
import { useImportUnits } from "../import-units-context";
import { formatDate } from "@/lib/utils";
import { CalendarClock, FileSpreadsheet, Info } from "lucide-react";

interface ImportJobDetailsProps {
  // No props needed as we'll use the context
}

export function ImportJobDetails({}: ImportJobDetailsProps) {
  // Call all hooks at the top level in the same order on every render
  const { job } = useImportUnits();
  
  if (!job.currentJob) {
    return null;
  }

  // Check if the import definition has a time_context_ident - if yes, it uses time context
  const hasTimeContext = !!job.currentDefinition?.time_context_ident;
  
  // Determine import type based on the job's slug
  const getImportType = () => {
    const slug = job.currentJob?.slug;
    if (!slug) return "Unknown Import Type";
    
    if (slug.includes("legal_unit")) return "Legal Units";
    if (slug.includes("establishment_for_lu")) return "Establishments with Legal Units";
    if (slug.includes("establishment_without_lu")) return "Establishments without Legal Units";
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
                {job.currentJob?.default_valid_from ? 
                  formatDate(new Date(job.currentJob.default_valid_from)) : 
                  "Not specified"}
              </span>
            </div>
            
            <div className="flex justify-between">
              <span className="text-gray-600">Valid To:</span>
              <span className="font-medium">
                {job.currentJob?.default_valid_to ? 
                  (job.currentJob.default_valid_to === "infinity" ? 
                    "Present (infinity)" : 
                    formatDate(new Date(job.currentJob.default_valid_to))) : 
                  "Not specified"}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
