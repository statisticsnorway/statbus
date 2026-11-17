import { notesWrite } from "./unit-notes";

// A unit's notes (owner 2026-11-17): one timeless text per unit in the side
// column; adding the first note, editing it and emptying it each map to one
// write on public.unit_notes.
describe("notesWrite", () => {
  const unit = { column: "legal_unit_id" as const, id: 29 };
  it("inserts the unit's first note", () => {
    expect(notesWrite(null, "Called them 3 Nov.\nNew address soon.", unit)).toEqual({
      kind: "insert",
      row: { legal_unit_id: 29, notes: "Called them 3 Nov.\nNew address soon." },
    });
  });
  it("writes nothing for an empty first note", () => {
    expect(notesWrite(null, "   ", unit)).toEqual({ kind: "none" });
  });
  it("updates a changed note, keeping quotes, commas and line breaks", () => {
    expect(notesWrite({ id: 7, notes: "old" }, ' said "yes", then\r\nleft ', unit)).toEqual({
      kind: "update",
      id: 7,
      notes: 'said "yes", then\r\nleft',
    });
  });
  it("writes nothing when the note is unchanged", () => {
    expect(notesWrite({ id: 7, notes: "same" }, "same\n", unit)).toEqual({ kind: "none" });
  });
  it("deletes the row when the note is emptied", () => {
    expect(notesWrite({ id: 7, notes: "old" }, "", unit)).toEqual({ kind: "delete", id: 7 });
  });
});
