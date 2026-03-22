"use client";

import { Suspense, useState } from "react";
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
import { getBrowserRestClient } from "@/context/RestClientStore";
import { toast } from "@/hooks/use-toast";
import { StepIndicator } from "../components/step-indicator";
import { BasicsStep } from "../components/basics-step";
import { SourceColumnsStep } from "../components/source-columns-step";
import { MappingStep } from "../components/mapping-step";
import { SummaryStep } from "../components/summary-step";

export default function NewDefinitionPage() {
  return (
    <Suspense>
      <NewDefinitionContent />
    </Suspense>
  );
}

function NewDefinitionContent() {
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
      const msg = err instanceof Error ? err.message : String(err);
      const isDuplicate = msg.includes("duplicate") || msg.includes("unique");
      toast({
        title: isDuplicate
          ? "A definition with a similar name already exists. Please choose a different name."
          : `Failed to create definition: ${msg}`,
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
      const refreshedMappings = await doFetchMappings(definition.id);
      setMappings(refreshedMappings);

      // Re-fetch definition for updated validation state
      const client = await getBrowserRestClient();
      const { data } = await client.from("import_definition").select("*").eq("id", definition.id).single();
      if (data) setDefinition(data);
    }
  };

  const handleStepClick = (targetStep: number) => {
    if (targetStep < step) {
      // After definition is created (step >= 2), don't allow going back to 0-1
      if (definition && targetStep < 2) return;
      setStep(targetStep);
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
          onBack={definition ? undefined : () => setStep(1)}
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
