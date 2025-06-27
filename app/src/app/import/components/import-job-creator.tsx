"use client";

import React, { useState } from "react";
import { useImportManager } from "@/atoms/hooks"; // Updated import
import { Button } from "@/components/ui/button";
import { useRouter } from "next/navigation";
import { Spinner } from "@/components/ui/spinner";

interface ImportJobCreatorProps {
  definitionSlug: string;
  uploadPath: string;
  unitType: string;
  onJobCreated?: () => void;
}

export function ImportJobCreator({ definitionSlug, uploadPath, unitType, onJobCreated }: ImportJobCreatorProps) {
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { 
    createImportJob, 
    timeContext: { selectedContext, useExplicitDates } 
  } = useImportManager(); // Updated hook call
  const router = useRouter();

  const handleContinue = async () => {
    if (!selectedContext && !useExplicitDates) {
      setError("Please select a time context or enable explicit dates");
      return;
    }

    setIsCreating(true);
    setError(null);

    try {
      // Use the appropriate definition slug.
      // The default definition `..._current_year` has a hardcoded time context which overrides any user selection.
      // To honor the user's choice (either a selected time context or explicit dates from CSV),
      // we must use a definition that does NOT have a hardcoded time context.
      // The `..._explicit_dates` definition serves this purpose for both cases.
      // - If a time context is selected, `createImportJobAtom` will populate `default_valid_from/to`.
      // - If explicit dates is chosen, `createImportJobAtom` will not, and the backend expects dates in the CSV.
      const actualDefinitionSlug = definitionSlug.replace('_current_year', '_explicit_dates');
        
      const job = await createImportJob(actualDefinitionSlug);
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
