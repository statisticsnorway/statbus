"use client";

import { useMemo, useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { format } from "date-fns";
import { Pencil } from "lucide-react";
import { restClientAtom } from "@/atoms/rest-client";
import { currentUserAtom, usePermission } from "@/atoms/auth";
import { useBaseData } from "@/atoms/base-data";
import { Button } from "@/components/ui/button";
import { notesWrite, type NotesUnitColumn } from "./unit-notes";

interface UnitNotesRow {
  id: number;
  notes: string;
  edit_by_user_id: number;
  edit_at: string;
}

/**
 * The unit's notes in the side column of every page of the unit (owner
 * 2026-11-17): a yellow sticky note, visible from every tab, growing with the
 * text, with a pencil at the right of its heading to add or edit it. Under the
 * text: who last wrote it and when. Notes are timeless, so the page's time
 * frame does not touch them. Reads and writes public.unit_notes directly (RLS
 * decides who may write); the box saves on Save, and Cancel restores the
 * stored text.
 */
export function UnitNotesBox({ column, unitId }: { column: NotesUnitColumn; unitId: number }) {
  const client = useAtomValue(restClientAtom);
  const currentUser = useAtomValue(currentUserAtom);
  const { canEdit } = usePermission();
  const { statbusUsers } = useBaseData();
  const key = client && unitId ? ["unit-notes", column, unitId] : null;
  const { data, mutate } = useSWR(key, async () => {
    const { data: rows, error } = await client!
      .from("unit_notes")
      .select("id,notes,edit_by_user_id,edit_at")
      .eq(column, unitId)
      .limit(1);
    if (error) throw error;
    return (rows?.[0] as UnitNotesRow | undefined) ?? null;
  });
  const stored = data?.notes ?? "";
  const writer = useMemo(
    () => (data ? statbusUsers.find((u) => u.id === data.edit_by_user_id)?.display_name : undefined),
    [data, statbusUsers]
  );
  // The draft starts from the stored text each time the box opens (begin).
  const [text, setText] = useState("");
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Set when a save found the note changed by someone else since it was
  // loaded: the box has reloaded their text, and the draft is kept.
  const [conflict, setConflict] = useState(false);
  const begin = () => {
    setText(stored);
    setError(null);
    setConflict(false);
    setEditing(true);
  };

  const save = async () => {
    if (!client || !currentUser) return;
    const write = notesWrite(
      data ? { id: data.id, notes: data.notes, edit_at: data.edit_at } : null,
      text,
      { column, id: unitId },
      { userId: currentUser.uid, at: new Date().toISOString() }
    );
    setSaving(true);
    setError(null);
    // An update or delete applies only to the version loaded (edit_at), and
    // returns the rows it touched: none means someone else saved meanwhile.
    const result =
      write.kind === "insert"
        ? await client.from("unit_notes").insert(write.row as never).select("id")
        : write.kind === "update"
          ? await client
              .from("unit_notes")
              .update(write.changes as never)
              .eq("id", write.id)
              .eq("edit_at", write.loadedEditAt)
              .select("id")
          : write.kind === "delete"
            ? await client
                .from("unit_notes")
                .delete()
                .eq("id", write.id)
                .eq("edit_at", write.loadedEditAt)
                .select("id")
            : { error: null, data: [{}] };
    setSaving(false);
    const firstNoteTaken = write.kind === "insert" && result.error?.code === "23505";
    const changedMeanwhile = write.kind !== "insert" && !result.error && (result.data?.length ?? 0) === 0;
    if (firstNoteTaken || changedMeanwhile) {
      await mutate();
      setConflict(true);
      return;
    }
    if (result.error) {
      setError(result.error.message);
      return;
    }
    await mutate();
    setConflict(false);
    setEditing(false);
  };

  if (data === undefined) return null;
  return (
    <section
      className="mt-4 rounded-sm border border-yellow-200 bg-yellow-50 p-3 text-sm text-zinc-900 shadow-sm"
      data-unit-notes=""
    >
      <div className="mb-1 flex items-center justify-between">
        <h3 className="text-xs font-medium uppercase tracking-wide text-yellow-900/70">Notes</h3>
        {canEdit && !editing && (
          <button
            type="button"
            className="rounded p-1 text-yellow-900/70 hover:bg-yellow-100 hover:text-yellow-950"
            onClick={begin}
            aria-label={stored ? "Edit the note" : "Add a note"}
            title={stored ? "Edit the note" : "Add a note"}
            data-unit-notes-edit=""
          >
            <Pencil className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
      {editing ? (
        <div className="space-y-2">
          {conflict && (
            <div className="rounded border border-amber-300 bg-amber-50 p-2 text-xs" data-unit-notes-conflict="">
              <p className="font-medium text-amber-900">
                {data
                  ? `${writer ?? "Someone"} saved this note at ${format(new Date(data.edit_at), "yyyy-MM-dd HH:mm")} while you were editing. Their text:`
                  : "Someone removed this note while you were editing."}
              </p>
              {data && <p className="mt-1 whitespace-pre-wrap break-words text-zinc-900">{data.notes}</p>}
              <p className="mt-1 text-amber-900">Your text is kept below. Save replaces theirs; Cancel keeps it.</p>
            </div>
          )}
          <textarea
            className="block w-full resize-y rounded border border-yellow-200 bg-white p-2 text-sm [field-sizing:content] min-h-20"
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
                setConflict(false);
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
          <p className="mt-2 text-xs text-yellow-900/70" data-unit-notes-written="">
            {writer ?? "Unknown user"}, {format(new Date(data!.edit_at), "yyyy-MM-dd HH:mm")}
          </p>
        </div>
      ) : (
        <p className="italic text-yellow-900/60">No notes</p>
      )}
    </section>
  );
}
