"use client";

import React from "react";
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
  return (
    <div className="border rounded-md p-4">
      <h3 className="font-medium mb-3">Import Configuration</h3>
      <div className="space-y-1 text-sm">
        <div className="flex justify-between items-center">
          <span className="text-gray-600">Description</span>
          <span className="font-medium text-right">{job.description}</span>
        </div>
      </div>
    </div>
  );
}
