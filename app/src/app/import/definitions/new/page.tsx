"use client";

import { useState } from "react";
import { useSearchParams } from "next/navigation";
import { useSetAtom } from "jotai";
import { usePermission } from "@/atoms/auth";
import {
  createDefinitionAtom,
  fetchDefinitionMappingsAtom,
  fetchAvailableTargetColumnsAtom,
  updateMappingAtom,
} from "@/atoms/definition-editor";
import type { Tables, Enums } from "@/lib/database.types";
import type { MappingWithDetails } from "@/atoms/definition-editor";
import { toast } from "@/hooks/use-toast";
import { StepIndicator } from "../components/step-indicator";
import { BasicsStep } from "../components/basics-step";
import { SourceColumnsStep } from "../components/source-columns-step";
import { MappingStep } from "../components/mapping-step";
import { SummaryStep } from "../components/summary-step";

export default function NewDefinitionPage() {
  const searchParams = useSearchParams();
  const { canAccessAdminTools } = usePermission();

  // Wizard state
  const [step, setStep] = useState(0);
  const [name, setName] = useState("");
  const [mode, setMode] = useState<Enums<"import_mode"> | null>(
    (searchParams.get("mode") as Enums<"import_mode">) || null,
  );
  const [strategy, setStrategy] = useState<Enums<"import_strategy">>("insert_or_replace");
  const [validTimeFrom, setValidTimeFrom] = useState<Enums<"import_valid_time_from">>("job_provided");
  const [note, setNote] = useState("");
  const [sourceColumns, setSourceColumns] = useState<string[]>([]);

  // Created definition state
  const [definition, setDefinition] = useState<Tables<"import_definition"> | null>(null);
  const [mappings, setMappings] = useState<MappingWithDetails[]>([]);
  const [targetColumns, setTargetColumns] = useState<Tables<"import_data_column">[]>([]);
  const [saving, setSaving] = useState(false);

  // Atoms
  const doCreateDefinition = useSetAtom(createDefinitionAtom);
  const doFetchMappings = useSetAtom(fetchDefinitionMappingsAtom);
  const doFetchTargetColumns = useSetAtom(fetchAvailableTargetColumnsAtom);
  const doUpdateMapping = useSetAtom(updateMappingAtom);

  if (!canAccessAdminTools) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        You do not have permission to create import definitions.
      </div>
    );
  }

  const handleTransitionToMappings = async () => {
    if (!mode) return;
    setSaving(true);
    try {
      // Create definition + link steps + create mappings
      const def = await doCreateDefinition({
        name,
        mode,
        strategy,
        valid_time_from: validTimeFrom,
        note: note || null,
        sourceColumns,
      });
      setDefinition(def);

      // Fetch generated mappings and available targets
      const [fetchedMappings, fetchedTargets] = await Promise.all([
        doFetchMappings(def.id),
        doFetchTargetColumns(def.id),
      ]);
      setMappings(fetchedMappings);
      setTargetColumns(fetchedTargets);
      setStep(2);
    } catch (err) {
      toast({
        title: `Failed to create definition: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateMapping = async (
    mappingId: number,
    targetDataColumnId: number | null,
    isIgnored: boolean,
  ) => {
    await doUpdateMapping({ mappingId, targetDataColumnId, isIgnored });
    // Refresh mappings and definition (validation may have changed)
    if (definition) {
      const [refreshedMappings] = await Promise.all([
        doFetchMappings(definition.id),
      ]);
      setMappings(refreshedMappings);

      // Re-fetch definition for updated validation state
      // We use the restClientAtom indirectly through our atoms, but the simplest
      // approach is to read from the mapping response or just refresh
      const { getBrowserRestClient } = await import("@/context/RestClientStore");
      const client = await getBrowserRestClient();
      const { data } = await client.from("import_definition").select("*").eq("id", definition.id).single();
      if (data) setDefinition(data);
    }
  };

  const handleStepClick = (targetStep: number) => {
    // Only allow going back, not forward (forward requires validation)
    if (targetStep < step) {
      // If definition already created, can freely navigate between steps 2-3
      if (targetStep >= 2 || !definition) {
        setStep(targetStep);
      } else {
        setStep(targetStep);
      }
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Create Import Definition</h1>
      <StepIndicator currentStep={step} onStepClick={handleStepClick} />

      {step === 0 && (
        <BasicsStep
          name={name}
          onNameChange={setName}
          mode={mode}
          onModeChange={setMode}
          strategy={strategy}
          onStrategyChange={setStrategy}
          validTimeFrom={validTimeFrom}
          onValidTimeFromChange={setValidTimeFrom}
          note={note}
          onNoteChange={setNote}
          onNext={() => setStep(1)}
        />
      )}

      {step === 1 && (
        <SourceColumnsStep
          columns={sourceColumns}
          onColumnsChange={setSourceColumns}
          onBack={() => setStep(0)}
          onNext={handleTransitionToMappings}
        />
      )}

      {step === 2 && definition && (
        <MappingStep
          mappings={mappings}
          availableTargetColumns={targetColumns}
          validationError={definition.validation_error}
          isValid={definition.valid}
          onUpdateMapping={handleUpdateMapping}
          onBack={() => setStep(1)}
          onNext={() => setStep(3)}
          loading={saving}
        />
      )}

      {step === 3 && definition && (
        <SummaryStep
          definition={definition}
          mappings={mappings}
          onBack={() => setStep(2)}
        />
      )}
    </div>
  );
}
