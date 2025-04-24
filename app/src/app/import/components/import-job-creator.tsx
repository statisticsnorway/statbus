"use client";

import React, { useState } from "react";
import { useImportUnits } from "../import-units-context";
import { Button } from "@/components/ui/button";
import { useRouter } from "next/navigation";
import { Spinner } from "@/components/ui/spinner";

interface ImportJobCreatorProps {
  definitionSlug: string;
  uploadPath: string;
  unitType: string;
}

export function ImportJobCreator({ definitionSlug, uploadPath, unitType }: ImportJobCreatorProps) {
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { 
    createImportJob, 
    timeContext: { selectedContext, useExplicitDates } 
  } = useImportUnits();
  const router = useRouter();

  const handleContinue = async () => {
    if (!selectedContext && !useExplicitDates) {
      setError("Please select a time context or enable explicit dates");
      return;
    }

    setIsCreating(true);
    setError(null);

    try {
      // Use the appropriate definition slug based on explicit dates selection
      const actualDefinitionSlug = useExplicitDates 
        ? definitionSlug.replace('_current_year', '_explicit_dates')
        : definitionSlug;
        
      const job = await createImportJob(actualDefinitionSlug);
      if (job) {
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
