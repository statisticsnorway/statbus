"use client";

import React, { useState } from "react";
import { useImportManager, ImportMode } from "@/atoms/import"; // Updated import
import { Button } from "@/components/ui/button";
import { useSetAtom } from "jotai";
import { pendingRedirectAtom } from "@/atoms/app";
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
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);

  // Load the definition for this import mode when the component mounts
  React.useEffect(() => {
    loadDefinitions(importMode);
  }, [loadDefinitions, importMode]);

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
      // The createImportJob atom now gets the definition from the state,
      // so it no longer needs the mode to be passed.
      const job = await createImportJob();
      if (job) {
        onJobCreated?.();
        setPendingRedirect(`${uploadPath}/${job.slug}`);
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
