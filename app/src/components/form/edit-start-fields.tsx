"use client";

import { useEditManager } from "@/atoms/edits";
import { editStartFields } from "./edit-payload";
import type { EditStartValues } from "./edit-values";

/**
 * The hidden fields that let a save keep each ticked period's own values
 * (edit-payload): what the edit started from, and whether the user chose the
 * data source or wrote the comment. Rendered inside the edit's form; without
 * a start (no rows read yet, a new record) nothing is posted and the save
 * writes every field.
 */
export function EditStartFields({ start }: { start: EditStartValues | null }) {
  const { currentEdit } = useEditManager();
  if (!start) return null;
  const fields = editStartFields(start, {
    dataSource: !!currentEdit.dataSourceChosen,
    comment: !!currentEdit.commentChosen,
  });
  return (
    <>
      {Object.entries(fields).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
    </>
  );
}
