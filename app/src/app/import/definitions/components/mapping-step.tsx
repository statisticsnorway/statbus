"use client";

import { useState } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import type { Tables } from "@/lib/database.types";
import type { MappingWithDetails } from "@/atoms/definition-editor";

interface MappingStepProps {
  mappings: MappingWithDetails[];
  availableTargetColumns: Tables<"import_data_column">[];
  validationError: string | null;
  isValid: boolean;
  onUpdateMapping: (mappingId: number, targetDataColumnId: number | null, isIgnored: boolean) => Promise<void>;
  onBack: () => void;
  onNext: () => void;
  loading?: boolean;
}

export function MappingStep({
  mappings,
  availableTargetColumns,
  validationError,
  isValid,
  onUpdateMapping,
  onBack,
  onNext,
  loading,
}: MappingStepProps) {
  const [updatingId, setUpdatingId] = useState<number | null>(null);

  // Only show source-column-backed mappings (skip expression-based like valid_from defaults)
  const sourceMappings = mappings.filter((m) => m.source_column_id !== null);

  // Group target columns by step for better organization
  const usedTargetIds = new Set(
    mappings.filter((m) => !m.is_ignored && m.target_data_column_id).map((m) => m.target_data_column_id),
  );

  const handleTargetChange = async (mapping: MappingWithDetails, value: string) => {
    setUpdatingId(mapping.id);
    try {
      if (value === "ignored") {
        await onUpdateMapping(mapping.id, null, true);
      } else {
        await onUpdateMapping(mapping.id, parseInt(value, 10), false);
      }
    } finally {
      setUpdatingId(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner className="h-6 w-6 mr-2" />
        <span className="text-muted-foreground">Loading mappings...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {validationError && (
        <div className="bg-amber-50 border border-amber-200 text-amber-800 px-4 py-3 rounded text-sm">
          {validationError}
        </div>
      )}

      {sourceMappings.length === 0 ? (
        <p className="text-muted-foreground text-sm">No source column mappings found.</p>
      ) : (
        <div className="space-y-3">
          <div className="grid grid-cols-[1fr,auto,1fr] gap-2 text-xs font-medium text-muted-foreground px-1">
            <span>Source Column</span>
            <span />
            <span>Target Column</span>
          </div>
          {sourceMappings.map((mapping) => {
            const sourceName = mapping.import_source_column?.column_name ?? "?";
            const currentTargetId = mapping.is_ignored ? "ignored" : String(mapping.target_data_column_id ?? "");
            const isAutoMatched = !mapping.is_ignored && mapping.target_data_column_id !== null;

            return (
              <div
                key={mapping.id}
                className="grid grid-cols-[1fr,auto,1fr] gap-2 items-center"
              >
                <div className="flex items-center gap-2">
                  <span className="font-mono text-sm truncate">{sourceName}</span>
                  {isAutoMatched && (
                    <Badge variant="outline" className="text-xs shrink-0">
                      auto
                    </Badge>
                  )}
                </div>
                <span className="text-muted-foreground">&rarr;</span>
                <div className="flex items-center gap-2">
                  <Select
                    value={currentTargetId}
                    onValueChange={(v) => handleTargetChange(mapping, v)}
                    disabled={updatingId === mapping.id}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Select target..." />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ignored">
                        <span className="text-muted-foreground">Ignored</span>
                      </SelectItem>
                      {availableTargetColumns.map((tc) => {
                        const inUse = usedTargetIds.has(tc.id) && tc.id !== mapping.target_data_column_id;
                        return (
                          <SelectItem
                            key={tc.id}
                            value={String(tc.id)}
                            disabled={inUse}
                          >
                            {tc.column_name.replace(/_raw$/, "")}
                            {inUse && " (in use)"}
                          </SelectItem>
                        );
                      })}
                    </SelectContent>
                  </Select>
                  {updatingId === mapping.id && <Spinner className="h-4 w-4" />}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="flex items-center gap-2 text-sm">
        <span className={isValid ? "text-green-600" : "text-amber-600"}>
          {isValid ? "\u2713 Definition is valid" : "\u26A0 Definition has validation issues"}
        </span>
      </div>

      <div className="flex justify-between">
        <Button variant="outline" onClick={onBack}>
          Back
        </Button>
        <Button onClick={onNext}>Next</Button>
      </div>
    </div>
  );
}
