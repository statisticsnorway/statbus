"use client";

import React, { useState } from "react";
import { useAtom } from "jotai";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { importValidityModeAtom, useImportManager } from "@/atoms/import";
import { useDetailsPageData } from "@/atoms/edits";
import { Spinner } from "@/components/ui/spinner";
import { TimeFramePanel, type ValidityChoice } from "@/components/time-frame-panel";

interface ImportTimeFrameSelectorProps {
  unitType: "legal-units" | "establishments" | "establishments-without-legal-unit" | "legal-relationships";
}

/**
 * Where an import's rows apply and where they come from (TimeFramePanel, the
 * same panel as the edit form). Simple: one Time frame. Advanced: Frame,
 * Dates or Source dates. Frame and Dates use the page's job_provided
 * definition; Source dates its source_columns definition. Data source and
 * Comment go onto the job (default_data_source_code, edit_comment).
 */
export function ImportTimeFrameSelector({ unitType }: ImportTimeFrameSelectorProps) {
  const {
    importState: { selectedDefinition, availableDefinitions, useExplicitDates, explicitStartDate, explicitEndDate, dataSourceCode, editComment },
    timeFrame: { availableTimeFrames, selectedTimeFrame },
    setSelectedTimeFrame,
    setSelectedDefinition,
    setUseExplicitDates,
    setExplicitStartDate,
    setExplicitEndDate,
    setDataSourceCode,
    setEditComment,
  } = useImportManager();
  const { dataSources } = useDetailsPageData();
  const [mode, setMode] = useAtom(importValidityModeAtom);

  const [isClient, setIsClient] = useState(false);
  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'ImportTimeFrameSelector:setIsClient');

  const jobProvidedDef = availableDefinitions.find((d) => d.valid_time_from === "job_provided");
  const sourceColumnsDef = availableDefinitions.find((d) => d.valid_time_from === "source_columns");

  const choice: ValidityChoice =
    selectedDefinition?.valid_time_from === "source_columns"
      ? "source_dates"
      : useExplicitDates
        ? "dates"
        : "frame";

  const handleChoiceChange = (next: ValidityChoice) => {
    if (next === "source_dates") {
      if (sourceColumnsDef) setSelectedDefinition(sourceColumnsDef);
      setUseExplicitDates(false);
    } else {
      if (jobProvidedDef) setSelectedDefinition(jobProvidedDef);
      setUseExplicitDates(next === "dates");
    }
  };

  // Simple always means a frame; dates typed in Advanced stay for when it opens again.
  const handleModeChange = (next: "simple" | "advanced") => {
    setMode(next);
    if (next === "simple") handleChoiceChange("frame");
  };

  // The definition's own source, shown until the user picks another.
  const definitionSource = dataSources.find((d) => d.id === selectedDefinition?.data_source_id);

  if (!isClient || !selectedDefinition || availableDefinitions.length === 0) {
    return (
      <div className="flex h-24 items-center justify-center rounded-md border bg-zinc-50 p-3">
        <Spinner message="Loading import definition..." />
      </div>
    );
  }

  return (
    <TimeFramePanel
      idPrefix={`import-${unitType}`}
      timeFrames={availableTimeFrames}
      mode={mode}
      onModeChange={handleModeChange}
      choice={choice}
      onChoiceChange={handleChoiceChange}
      frameIdent={selectedTimeFrame?.ident ?? null}
      onFrameChange={setSelectedTimeFrame}
      validFrom={explicitStartDate}
      validTo={explicitEndDate}
      onValidFromChange={setExplicitStartDate}
      onValidToChange={setExplicitEndDate}
      sourceDates={
        sourceColumnsDef
          ? { label: sourceColumnsDef.name, description: "Each row's valid_from and valid_to columns in the file." }
          : undefined
      }
      dataSources={dataSources}
      dataSourceCode={dataSourceCode ?? definitionSource?.code ?? null}
      onDataSourceChange={setDataSourceCode}
      dataSourcePlaceholder="From the file or the definition"
      comment={editComment}
      onCommentChange={setEditComment}
    />
  );
}
