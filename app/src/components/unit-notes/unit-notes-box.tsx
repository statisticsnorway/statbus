"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { format } from "date-fns";
import { ChevronDown, ChevronRight, Pencil } from "lucide-react";
import { restClientAtom } from "@/atoms/rest-client";
import { currentUserAtom, usePermission } from "@/atoms/auth";
import { useBaseData } from "@/atoms/base-data";
import { Button } from "@/components/ui/button";
import { notesWrite } from "./unit-notes";
import type { ChainUnit } from "./primary-chain";

interface UnitNotesRow {
  id: number;
  notes: string;
  edit_by_user_id: number;
  edit_at: string;
}

/** A unit's stored note (public.unit_notes), null when it has none; undefined while loading. */
function useUnitNote(unit: ChainUnit) {
  const client = useAtomValue(restClientAtom);
  const key = client ? ["unit-notes", unit.column, unit.id] : null;
  return useSWR(key, async () => {
    const { data: rows, error } = await client!
      .from("unit_notes")
      .select("id,notes,edit_by_user_id,edit_at")
      .eq(unit.column, unit.id)
      .limit(1);
    if (error) throw error;
    return (rows?.[0] as UnitNotesRow | undefined) ?? null;
  });
}

function useWriterName(row: UnitNotesRow | null | undefined) {
  const { statbusUsers } = useBaseData();
  return useMemo(
    () => (row ? statbusUsers.find((u) => u.id === row.edit_by_user_id)?.display_name : undefined),
    [row, statbusUsers]
  );
}

/** Who last wrote a note and when, on two lines so neither breaks. */
function WrittenBy({ writer, at }: { writer: string | null | undefined; at: string }) {
  return (
    <p className="mt-1 text-xs text-yellow-900/70" data-unit-notes-written="">
      <span className="block">{writer ?? "Unknown user"}</span>
      <span className="block">{format(new Date(at), "yyyy-MM-dd HH:mm")}</span>
    </p>
  );
}

/**
 * The notes in the side column of every page of a unit (owner 2026-11-17,
 * n9nyvd; the chain 2026-11-20 and 2026-11-21, 64ae2w). The page's own unit
 * is on top: the yellow sticky "Notes", open, with a pencil to add or edit
 * it. Below it, the other units of the chain that have a note follow in the
 * chain's fixed order (primaryChain: enterprise, legal unit, establishment),
 * each a small post-it named by its role ("Primary legal unit note"),
 * collapsed: clicking its heading opens and closes it, and the unit's name
 * inside the opened note takes you to that unit's page, where it is edited.
 * Notes are timeless, so the page's time frame does not touch them.
 */
export function UnitNotesBox({ chain }: { chain: ChainUnit[] }) {
  const own = chain.find((u) => u.current);
  if (!own) return null;
  return (
    <div className="mt-4 space-y-2">
      <OwnNote unit={own} />
      {chain
        .filter((u) => !u.current)
        .map((unit) => (
          <RelatedNote key={`${unit.column}-${unit.id}`} unit={unit} />
        ))}
    </div>
  );
}

/** The page's own unit's note: read and written from here. */
function OwnNote({ unit }: { unit: ChainUnit }) {
  const client = useAtomValue(restClientAtom);
  const currentUser = useAtomValue(currentUserAtom);
  const { canEdit } = usePermission();
  const { data, mutate } = useUnitNote(unit);
  const stored = data?.notes ?? "";
  const writer = useWriterName(data);
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
      { column: unit.column, id: unit.id },
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
      className="rounded-sm border border-yellow-200 bg-yellow-50 p-3 text-sm text-zinc-900 shadow-sm"
      data-unit-notes=""
      data-unit-notes-unit={unit.column}
      data-unit-notes-current=""
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
          <WrittenBy writer={writer} at={data!.edit_at} />
        </div>
      ) : (
        <p className="italic text-yellow-900/60">No notes</p>
      )}
    </section>
  );
}

/**
 * Another unit of the chain's note, as a small post-it under the page's own
 * note: only when it has a note, collapsed until its heading is clicked,
 * read-only here.
 */
function RelatedNote({ unit }: { unit: ChainUnit }) {
  const { data } = useUnitNote(unit);
  const writer = useWriterName(data);
  const [open, setOpen] = useState(false);
  if (!data) return null;
  return (
    <section
      className="rounded-sm border border-yellow-200 bg-yellow-50/70 px-2.5 py-1.5 text-xs text-zinc-900 shadow-sm"
      data-unit-notes-related=""
      data-unit-notes-unit={unit.column}
      data-unit-notes-open={open ? "" : undefined}
    >
      <button
        type="button"
        className="flex w-full items-center justify-between gap-2 text-left text-yellow-900/80 hover:text-yellow-950"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        data-unit-notes-toggle=""
      >
        <span className="min-w-0 truncate font-medium" data-unit-notes-heading="">
          {unit.kind} note
        </span>
        <span className="flex shrink-0 items-center gap-0.5 text-yellow-900/70">
          {open ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
          {open ? "Hide" : "Show"}
        </span>
      </button>
      {open && (
        <div className="mt-1">
          <Link
            href={unit.href}
            className="block truncate text-sm font-medium underline underline-offset-2"
            data-unit-notes-name-link=""
          >
            {unit.name}
          </Link>
          <p className="whitespace-pre-wrap break-words text-sm" data-unit-notes-shown="">{data.notes}</p>
          <WrittenBy writer={writer} at={data.edit_at} />
        </div>
      )}
    </section>
  );
}
