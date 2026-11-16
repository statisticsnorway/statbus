"use client";

import { useState, type ReactNode } from "react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { useDescribeValue } from "./field-timeline-view";
import { DIFFERS, asFormValue } from "./edit-payload";
import type { EditStartValues, ValueRun } from "./edit-values";

const formatEnd = (to: string) => (to === "infinity" ? "Present" : to);

/** A run of a column's value in words: "4500 Investment trusts … (2024-01-01 – 2025-12-31)". */
function useDescribeRun() {
  const describe = useDescribeValue();
  return (column: string, run: ValueRun, source = false) => {
    const value = source
      ? describe.source(run.value as number | null)
      : describe.value({ [column]: run.value });
    return `${value ?? "Empty"} (${run.valid_from} – ${formatEnd(run.valid_to)})`;
  };
}

/**
 * Under a field whose ticked periods hold different values: what each holds.
 * The field shows "Differs" and the save keeps each period's own until the
 * user chooses a value (owner 2026-11-16). `label` names the field when the
 * note stands apart from it (a field group lists its differing fields).
 */
export function DiffersNote({
  column,
  start,
  current,
  label,
}: {
  column: string;
  start: EditStartValues | null;
  current: string;
  label?: string;
}) {
  const describeRun = useDescribeRun();
  const runs = start?.differences[column];
  if (!runs) return null;
  const chosen = current !== DIFFERS;
  return (
    <p className="text-xs text-amber-800" data-edit-differs={column}>
      {label && <span className="font-medium capitalize">{label}: </span>}
      {chosen ? "Replaces " : "Differs, each period keeps its own: "}
      {runs.map((r) => describeRun(column, r)).join("; ")}
    </p>
  );
}

/** Under the data source when the ticked periods have different ones. */
export function DataSourceDiffersNote({
  start,
  chosen,
}: {
  start: EditStartValues | null;
  chosen: boolean;
}) {
  const describeRun = useDescribeRun();
  if (!start || start.dataSourceRuns.length === 0) return null;
  return (
    <p className="text-xs text-amber-800" data-edit-differs="data_source_id">
      {chosen
        ? "Replaces the data source "
        : "Data source differs, each period keeps its own: "}
      {start.dataSourceRuns
        .map((r) => describeRun("data_source_id", r, true))
        .join("; ")}
    </p>
  );
}

/**
 * The differing values a save would replace: each differing column the form
 * now sets (it no longer posts DIFFERS), and the data source when the periods
 * differ and the user chose one.
 */
export function replacedValues(
  form: FormData,
  start: EditStartValues | null,
  dataSourceChosen: boolean
): { column: string; runs: ValueRun[]; source?: boolean }[] {
  if (!start) return [];
  const out: { column: string; runs: ValueRun[]; source?: boolean }[] = [];
  for (const [column, runs] of Object.entries(start.differences))
    if (form.has(column) && asFormValue(form.get(column)) !== DIFFERS)
      out.push({ column, runs });
  if (dataSourceChosen && start.dataSourceRuns.length > 0)
    out.push({
      column: "data_source_id",
      runs: start.dataSourceRuns,
      source: true,
    });
  return out;
}

/**
 * Asks before a save replaces values that differ between the ticked periods
 * (owner 2026-11-16): ticking periods never overwrites them, a save does only
 * after the user confirms. `ask(form, onConfirm)` returns false when nothing
 * differing is replaced, so the caller saves at once.
 */
export function useReplaceDifferingConfirmation(
  start: EditStartValues | null,
  dataSourceChosen: boolean,
  labels: Record<string, string>
) {
  const describeRun = useDescribeRun();
  const [pending, setPending] = useState<{
    items: ReturnType<typeof replacedValues>;
    action: () => void;
  } | null>(null);
  const ask = (form: FormData, onConfirm: () => void): boolean => {
    const items = replacedValues(form, start, dataSourceChosen);
    if (items.length === 0) return false;
    setPending({ items, action: onConfirm });
    return true;
  };
  const dialog: ReactNode = pending ? (
    <AlertDialog open onOpenChange={(open) => !open && setPending(null)}>
      <AlertDialogContent data-replace-differing-confirmation>
        <AlertDialogHeader>
          <AlertDialogTitle>Replace different values?</AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className="space-y-2">
              <p>
                The ticked periods hold different values. Saving gives them one
                value:
              </p>
              <ul className="list-disc pl-5 space-y-1">
                {pending.items.map((item) => (
                  <li key={item.column} data-replaced={item.column}>
                    <span className="font-medium">
                      {labels[item.column] ?? item.column.replace(/_/g, " ")}
                    </span>
                    :{" "}
                    {item.runs
                      .map((r) => describeRun(item.column, r, item.source))
                      .join("; ")}
                  </li>
                ))}
              </ul>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={() => setPending(null)}>
            Cancel
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={() => {
              const { action } = pending;
              setPending(null);
              action();
            }}
          >
            Replace
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  ) : null;
  return { ask, dialog };
}
