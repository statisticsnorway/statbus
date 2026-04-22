"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { useImportManager, ImportMode } from "@/atoms/import"; // Updated import
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { describeError } from "@/lib/error-format";

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
    setReview,
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
      setError(`Error creating import job: ${describeError(err)}`);
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

      <div className="flex items-center space-x-2 mb-4">
        <label htmlFor="review-mode" className="text-sm">
          Review mode
        </label>
        <Select
          value={importState.review === null ? "auto" : importState.review ? "always" : "never"}
          onValueChange={(value) => {
            if (value === "auto") setReview(null);
            else if (value === "always") setReview(true);
            else setReview(false);
          }}
        >
          <SelectTrigger id="review-mode" className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="auto">Review if errors</SelectItem>
            <SelectItem value="always">Always review</SelectItem>
            <SelectItem value="never">Never review</SelectItem>
          </SelectContent>
        </Select>
      </div>

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
