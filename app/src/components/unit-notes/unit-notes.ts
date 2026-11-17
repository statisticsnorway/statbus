/**
 * A unit's notes (owner 2026-11-17): one timeless text per unit, the user's
 * own working aid, stored in public.unit_notes (one row per unit, unique on
 * the unit's id columns). The notes box in the side column of every unit page
 * reads and writes it.
 */
export type NotesUnitColumn = "legal_unit_id" | "establishment_id" | "enterprise_id" | "power_group_id";

export type NotesWrite =
  | { kind: "none" }
  | { kind: "insert"; row: Record<string, string | number> }
  | { kind: "update"; id: number; changes: { notes: string; edit_by_user_id: number; edit_at: string } }
  | { kind: "delete"; id: number };

/** Who saves the note and when: the row's edit_by_user_id and edit_at. */
export interface NotesEditor {
  userId: number;
  at: string;
}

/**
 * What saving the notes box does: a first text inserts the unit's row, a
 * changed text updates it, an emptied box deletes it (the table holds only
 * real notes: notes is NOT NULL), and an unchanged text writes nothing.
 * Leading and trailing white space is not kept. An update names its editor
 * and time, since the row's edit_by_user_id and edit_at tell who wrote the
 * text shown (an insert gets both from the column defaults, auth.uid() and
 * statement_timestamp()).
 */
export function notesWrite(
  existing: { id: number; notes: string } | null,
  text: string,
  unit: { column: NotesUnitColumn; id: number },
  editor: NotesEditor
): NotesWrite {
  const notes = text.trim();
  if (!existing) return notes ? { kind: "insert", row: { [unit.column]: unit.id, notes } } : { kind: "none" };
  if (!notes) return { kind: "delete", id: existing.id };
  if (notes === existing.notes) return { kind: "none" };
  return { kind: "update", id: existing.id, changes: { notes, edit_by_user_id: editor.userId, edit_at: editor.at } };
}
