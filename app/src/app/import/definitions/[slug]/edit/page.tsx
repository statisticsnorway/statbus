"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { useSetAtom } from "jotai";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { usePermission } from "@/atoms/auth";
import { getBrowserRestClient } from "@/context/RestClientStore";
import {
  fetchDefinitionMappingsAtom,
  fetchAvailableTargetColumnsAtom,
  fetchSourceColumnsAtom,
  updateMappingAtom,
  updateDefinitionAtom,
  addSourceColumnAtom,
  removeSourceColumnAtom,
} from "@/atoms/definition-editor";
import type { Tables, Enums } from "@/lib/database.types";
import type { MappingWithDetails } from "@/atoms/definition-editor";
import { toast } from "@/hooks/use-toast";
import { Spinner } from "@/components/ui/spinner";
import { StepIndicator } from "../../components/step-indicator";
import { BasicsStep } from "../../components/basics-step";
import { EditSourceColumnsStep } from "./edit-source-columns-step";
import { MappingStep } from "../../components/mapping-step";
import { SummaryStep } from "../../components/summary-step";

export default function EditDefinitionPage() {
  const params = useParams<{ slug: string }>();
  const { canAccessAdminTools } = usePermission();

  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(true);
  const [definition, setDefinition] = useState<Tables<"import_definition"> | null>(null);
  const [sourceColumns, setSourceColumns] = useState<Tables<"import_source_column">[]>([]);
  const [mappings, setMappings] = useState<MappingWithDetails[]>([]);
  const [targetColumns, setTargetColumns] = useState<Tables<"import_data_column">[]>([]);

  // Edit form state
  const [name, setName] = useState("");
  const [strategy, setStrategy] = useState<Enums<"import_strategy">>("insert_or_replace");
  const [note, setNote] = useState("");

  const doFetchMappings = useSetAtom(fetchDefinitionMappingsAtom);
  const doFetchTargetColumns = useSetAtom(fetchAvailableTargetColumnsAtom);
  const doFetchSourceColumns = useSetAtom(fetchSourceColumnsAtom);
  const doUpdateMapping = useSetAtom(updateMappingAtom);
  const doUpdateDefinition = useSetAtom(updateDefinitionAtom);
  const doAddSourceColumn = useSetAtom(addSourceColumnAtom);
  const doRemoveSourceColumn = useSetAtom(removeSourceColumnAtom);

  const loadDefinition = async () => {
    setLoading(true);
    try {
      const client = await getBrowserRestClient();
      const { data: def, error } = await client
        .from("import_definition")
        .select("*")
        .eq("slug", params.slug)
        .eq("custom", true)
        .single();
      if (error) throw error;
      if (!def) throw new Error("Definition not found");

      setDefinition(def);
      setName(def.name);
      setStrategy(def.strategy);
      setNote(def.note ?? "");

      const [cols, maps, targets] = await Promise.all([
        doFetchSourceColumns(def.id),
        doFetchMappings(def.id),
        doFetchTargetColumns(def.id),
      ]);
      setSourceColumns(cols);
      setMappings(maps);
      setTargetColumns(targets);
    } catch (err) {
      toast({
        title: `Failed to load definition: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  useGuardedEffect(() => {
    if (canAccessAdminTools && params.slug) loadDefinition();
  }, [canAccessAdminTools, params.slug], "EditDefinitionPage:load");

  if (!canAccessAdminTools) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        You do not have permission to edit import definitions.
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner className="h-6 w-6" />
      </div>
    );
  }

  if (!definition) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        Definition not found.
      </div>
    );
  }

  const refreshAll = async () => {
    const client = await getBrowserRestClient();
    const { data: refreshedDef } = await client
      .from("import_definition")
      .select("*")
      .eq("id", definition.id)
      .single();
    if (refreshedDef) setDefinition(refreshedDef);

    const [cols, maps, targets] = await Promise.all([
      doFetchSourceColumns(definition.id),
      doFetchMappings(definition.id),
      doFetchTargetColumns(definition.id),
    ]);
    setSourceColumns(cols);
    setMappings(maps);
    setTargetColumns(targets);
  };

  const handleSaveBasics = async () => {
    try {
      const updated = await doUpdateDefinition({
        id: definition.id,
        name,
        strategy,
        note: note || null,
      });
      setDefinition(updated);
      setStep(1);
    } catch (err) {
      toast({
        title: `Failed to save: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    }
  };

  const handleAddColumn = async (columnName: string, ignored: boolean) => {
    // Errors propagate: the step offers "Add as ignored" for unreadable names.
    await doAddSourceColumn({ definitionId: definition.id, columnName, ignored });
    await refreshAll();
  };

  const handleRemoveColumn = async (sourceColumnId: number) => {
    try {
      await doRemoveSourceColumn(sourceColumnId);
      await refreshAll();
    } catch (err) {
      toast({
        title: `Failed to remove column: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    }
  };

  const handleUpdateMapping = async (
    mappingId: number,
    targetDataColumnId: number | null,
    isIgnored: boolean,
  ) => {
    try {
      await doUpdateMapping({ mappingId, targetDataColumnId, isIgnored });
      await refreshAll();
    } catch (err) {
      toast({
        title: `Failed to update mapping: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Edit: {definition.name}</h1>
      <StepIndicator currentStep={step} onStepClick={(s) => setStep(s)} />

      {step === 0 && (
        <BasicsStep
          name={name}
          onNameChange={setName}
          mode={definition.mode}
          strategy={strategy}
          onStrategyChange={setStrategy}
          validTimeFrom={definition.valid_time_from}
          note={note}
          onNoteChange={setNote}
          onNext={handleSaveBasics}
          isEditMode
        />
      )}

      {step === 1 && (
        <EditSourceColumnsStep
          sourceColumns={sourceColumns}
          ignoredSourceColumnIds={
            new Set(
              mappings
                .filter((m) => m.is_ignored && m.source_column_id !== null)
                .map((m) => m.source_column_id as number),
            )
          }
          onAddColumn={handleAddColumn}
          onRemoveColumn={handleRemoveColumn}
          onBack={() => setStep(0)}
          onNext={() => setStep(2)}
        />
      )}

      {step === 2 && (
        <MappingStep
          mappings={mappings}
          availableTargetColumns={targetColumns}
          validationError={definition.validation_error}
          isValid={definition.valid}
          onUpdateMapping={handleUpdateMapping}
          onBack={() => setStep(1)}
          onNext={() => setStep(3)}
        />
      )}

      {step === 3 && (
        <SummaryStep
          definition={definition}
          mappings={mappings}
          onBack={() => setStep(2)}
        />
      )}
    </div>
  );
}
