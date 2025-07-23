"use client";

import React, { useState } from "react";
import { useImportManager, ImportMode } from "@/atoms/import"; // Updated import
import { Button } from "@/components/ui/button";
import { useRouter } from "next/navigation";
import { Spinner } from "@/components/ui/spinner";

interface ImportJobCreatorProps {
  importMode: ImportMode;
  uploadPath: string;
  unitType: string;
  onJobCreated?: () => void;
}

export function ImportJobCreator({ importMode, uploadPath, unitType, onJobCreated }: ImportJobCreatorProps) {
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { 
    createImportJob, 
    timeContext: { selectedContext, useExplicitDates } 
  } = useImportManager(importMode); // Updated hook call
  const router = useRouter();

  const handleContinue = async () => {
    if (!selectedContext && !useExplicitDates) {
      setError("Please select a time context or enable explicit dates");
      return;
    }

    setIsCreating(true);
    setError(null);

    try {
      // The createImportJob atom now takes an importMode and will select the correct
      // import definition (the one without a hardcoded time context) on the backend.
      // This allows the user's choice of time context or explicit dates to be respected.
      const job = await createImportJob(importMode);
      if (job) {
        onJobCreated?.();
        router.push(`${uploadPath}/${job.slug}`);
      } else {
        setError("Failed to create import job");
      }
    } catch (err) {
      setError(`Error creating import job: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div className="mt-6">
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      <Button 
        onClick={handleContinue} 
        disabled={isCreating || (!selectedContext && !useExplicitDates)}
        className="w-full"
      >
        {isCreating ? <Spinner className="mr-2 h-4 w-4" /> : null}
        Continue to Upload {unitType}
      </Button>
    </div>
  );
}
