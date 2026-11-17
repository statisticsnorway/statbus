"use client";

import { useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { restClientAtom } from "@/atoms/rest-client";
import { usePermission } from "@/atoms/auth";
import { Button } from "@/components/ui/button";
import { notesWrite, type NotesUnitColumn } from "./unit-notes";

interface UnitNotesRow {
  id: number;
  notes: string;
  edit_at: string;
}

/**
 * The unit's notes in the side column of every page of the unit (owner
 * 2026-11-17): visible from every tab, growing with the text, and the place
 * to add the first note. Notes are timeless, so the page's time frame does
 * not touch them. Reads and writes public.unit_notes directly (RLS decides who
 * may write); the box saves on Save, and Cancel restores the stored text.
 */
export function UnitNotesBox({ column, unitId }: { column: NotesUnitColumn; unitId: number }) {
  const client = useAtomValue(restClientAtom);
  const { canEdit } = usePermission();
  const key = client && unitId ? ["unit-notes", column, unitId] : null;
  const { data, mutate } = useSWR(key, async () => {
    const { data: rows, error } = await client!
      .from("unit_notes")
      .select("id,notes,edit_at")
      .eq(column, unitId)
      .limit(1);
    if (error) throw error;
    return (rows?.[0] as UnitNotesRow | undefined) ?? null;
  });
  const stored = data?.notes ?? "";
  // The draft starts from the stored text each time the box opens (begin).
  const [text, setText] = useState("");
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const begin = () => {
    setText(stored);
    setError(null);
    setEditing(true);
  };

  const save = async () => {
    if (!client) return;
    const write = notesWrite(data ? { id: data.id, notes: data.notes } : null, text, { column, id: unitId });
    setSaving(true);
    setError(null);
    const result =
      write.kind === "insert"
        ? await client.from("unit_notes").insert(write.row as never)
        : write.kind === "update"
          ? await client.from("unit_notes").update({ notes: write.notes } as never).eq("id", write.id)
          : write.kind === "delete"
            ? await client.from("unit_notes").delete().eq("id", write.id)
            : { error: null };
    setSaving(false);
    if (result.error) {
      setError(result.error.message);
      return;
    }
    await mutate();
    setEditing(false);
  };

  if (data === undefined) return null;
  return (
    <section className="mt-4 rounded border border-zinc-200 bg-white p-3 text-sm" data-unit-notes="">
      <h3 className="mb-1 text-xs font-medium uppercase tracking-wide text-zinc-500">Notes</h3>
      {editing ? (
        <div className="space-y-2">
          <textarea
            className="block w-full resize-y rounded border border-zinc-300 p-2 text-sm [field-sizing:content] min-h-20"
            value={text}
            onChange={(e) => setText(e.target.value)}
            autoFocus
            aria-label="Notes"
            data-unit-notes-text=""
          />
          {error && <p className="text-red-700">{error}</p>}
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              className="h-7"
              onClick={() => {
                setEditing(false);
                setError(null);
              }}
            >
              Cancel
            </Button>
            <Button type="button" className="h-7" onClick={save} disabled={saving} data-unit-notes-save="">
              {saving ? "Saving…" : "Save"}
            </Button>
          </div>
        </div>
      ) : stored ? (
        <div>
          <p className="whitespace-pre-wrap break-words" data-unit-notes-shown="">{stored}</p>
          {canEdit && (
            <button type="button" className="mt-1 text-xs text-zinc-600 underline" onClick={begin} data-unit-notes-edit="">
              Edit note
            </button>
          )}
        </div>
      ) : canEdit ? (
        <button type="button" className="text-zinc-600 underline" onClick={begin} data-unit-notes-add="">
          Add a note
        </button>
      ) : (
        <p className="italic text-zinc-400">No notes</p>
      )}
    </section>
  );
}
