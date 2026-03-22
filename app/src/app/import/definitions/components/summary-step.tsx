"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useSetAtom } from "jotai";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/hooks/use-toast";
import { createImportJobFromDefinitionAtom } from "@/atoms/import";
import { getUploadPath } from "@/lib/import-mode-paths";
import type { Tables } from "@/lib/database.types";
import type { MappingWithDetails } from "@/atoms/definition-editor";
import { MODE_LABELS, STRATEGY_LABELS } from "./labels";

interface SummaryStepProps {
  definition: Tables<"import_definition">;
  mappings: MappingWithDetails[];
  onBack: () => void;
}

export function SummaryStep({ definition, mappings, onBack }: SummaryStepProps) {
  const router = useRouter();
  const createJob = useSetAtom(createImportJobFromDefinitionAtom);
  const [isCreating, setIsCreating] = useState(false);

  const mappedCount = mappings.filter((m) => !m.is_ignored && m.target_data_column_id).length;
  const ignoredCount = mappings.filter((m) => m.is_ignored).length;

  const handleCreateJob = async () => {
    setIsCreating(true);
    try {
      const job = await createJob({
        definitionId: definition.id,
        description: `Job from ${definition.name}`,
        timeContextIdent: null,
        defaultValidFrom: null,
        defaultValidTo: null,
        review: null,
      });
      toast({ title: `Created import job ${job.slug}` });
      router.push(getUploadPath(definition.mode, job.slug));
    } catch (err) {
      toast({
        title: `Failed to create job: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-muted/50 rounded-lg p-6 space-y-4">
        <h3 className="font-semibold text-lg">Definition Summary</h3>

        <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
          <span className="text-muted-foreground">Name</span>
          <span className="font-medium">{definition.name}</span>

          <span className="text-muted-foreground">Mode</span>
          <span>{MODE_LABELS[definition.mode] ?? definition.mode}</span>

          <span className="text-muted-foreground">Strategy</span>
          <span>{STRATEGY_LABELS[definition.strategy] ?? definition.strategy}</span>

          <span className="text-muted-foreground">Valid Time From</span>
          <span>{definition.valid_time_from === "job_provided" ? "Job provided" : "Source columns"}</span>

          <span className="text-muted-foreground">Mappings</span>
          <span>
            {mappedCount} mapped, {ignoredCount} ignored
          </span>

          <span className="text-muted-foreground">Status</span>
          <span>
            {definition.valid ? (
              <Badge className="bg-green-100 text-green-800 hover:bg-green-100">Valid</Badge>
            ) : (
              <Badge variant="destructive">Invalid</Badge>
            )}
          </span>
        </div>

        {definition.note && (
          <div>
            <span className="text-sm text-muted-foreground">Note: </span>
            <span className="text-sm">{definition.note}</span>
          </div>
        )}

        {definition.validation_error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded text-sm">
            {definition.validation_error}
          </div>
        )}
      </div>

      <div className="flex justify-between">
        <Button variant="outline" onClick={onBack}>
          Back
        </Button>
        {definition.valid ? (
          <Button onClick={handleCreateJob} disabled={isCreating}>
            {isCreating && <Spinner className="mr-2 h-4 w-4" />}
            Create Import Job
          </Button>
        ) : (
          <Button variant="outline" onClick={onBack}>
            Fix Issues
          </Button>
        )}
      </div>
    </div>
  );
}
