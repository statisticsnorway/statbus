import { notesWrite } from "./unit-notes";

// A unit's notes (owner 2026-11-17): one timeless text per unit in the side
// column; adding the first note, editing it and emptying it each map to one
// write on public.unit_notes.
describe("notesWrite", () => {
  const unit = { column: "legal_unit_id" as const, id: 29 };
  const editor = { userId: 4, at: "2026-11-17T19:20:00.000Z" };
  it("inserts the unit's first note", () => {
    expect(notesWrite(null, "Called them 3 Nov.\nNew address soon.", unit, editor)).toEqual({
      kind: "insert",
      row: { legal_unit_id: 29, notes: "Called them 3 Nov.\nNew address soon." },
    });
  });
  it("writes nothing for an empty first note", () => {
    expect(notesWrite(null, "   ", unit, editor)).toEqual({ kind: "none" });
  });
  it("updates a changed note, keeping quotes, commas and line breaks, naming its editor and time", () => {
    expect(notesWrite({ id: 7, notes: "old" }, ' said "yes", then\r\nleft ', unit, editor)).toEqual({
      kind: "update",
      id: 7,
      changes: { notes: 'said "yes", then\r\nleft', edit_by_user_id: 4, edit_at: "2026-11-17T19:20:00.000Z" },
    });
  });
  it("writes nothing when the note is unchanged", () => {
    expect(notesWrite({ id: 7, notes: "same" }, "same\n", unit, editor)).toEqual({ kind: "none" });
  });
  it("deletes the row when the note is emptied", () => {
    expect(notesWrite({ id: 7, notes: "old" }, "", unit, editor)).toEqual({ kind: "delete", id: 7 });
  });
});
