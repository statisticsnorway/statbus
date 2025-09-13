"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { useImportManager, ImportMode } from "@/atoms/import"; // Updated import
import { Button } from "@/components/ui/button";
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
    importState,
    loadDefinitions,
    timeContext,
  } = useImportManager();
  const router = useRouter();

  // Load the definition for this import mode when the component mounts
  useGuardedEffect(() => {
    loadDefinitions(importMode);
  }, [loadDefinitions, importMode], 'ImportJobCreator:loadDefinitions');

  const { useExplicitDates, explicitStartDate, explicitEndDate, selectedDefinition } = importState;
  const { selectedContext } = timeContext;

  const handleContinue = async () => {
    if (selectedDefinition?.valid_time_from === 'job_provided') {
      if (useExplicitDates) {
        if (!explicitStartDate || !explicitEndDate) {
          setError("Please provide both a start and end date.");
          return;
        }
      } else if (!selectedContext) {
        setError("Please select a time context.");
        return;
      }
    }

    setIsCreating(true);
    setError(null);

    try {
      const job = await createImportJob();
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
        disabled={isCreating || !selectedDefinition}
        className="w-full"
      >
        {isCreating ? <Spinner className="mr-2 h-4 w-4" /> : null}
        Continue to Upload {unitType}
      </Button>
    </div>
  );
}
