import { editPeriodInFrame } from "@/components/form/use-start-edit";

// STATBUS-606: an edit applies within a time frame. Without the field's rows the
// period is the frame; with them it is the shown value's stretch in the frame
// (STATBUS-604). The live frame's open end is held as an empty valid_to.
function fakeClient(rows: Record<string, unknown>[]) {
  const builder = {
    select() { return builder; },
    eq() { return builder; },
    order() { return Promise.resolve({ data: rows, error: null }); },
  };
  return { from() { return builder; } };
}

const live = { valid_from: "2026-01-01", valid_to: "infinity" };
const prev = { valid_from: "2025-01-01", valid_to: "2025-12-31" };
const y2024 = { valid_from: "2024-01-01", valid_to: "2024-12-31" };

describe("editPeriodInFrame", () => {
  it("is the frame when the edit has no field rows to read", async () => {
    expect(await editPeriodInFrame(null, live)).toEqual({ validFrom: "2026-01-01", validTo: null });
    expect(await editPeriodInFrame(null, prev)).toEqual({ validFrom: "2025-01-01", validTo: "2025-12-31" });
  });

  it("follows the chosen frame for the same field: live, then previous, then a fixed year", async () => {
    // A name held from 2020 onwards: each frame gives that frame's part of the stretch.
    const client = fakeClient([{ valid_from: "2020-03-01", valid_to: "infinity", name: "NORDLYS AS" }]);
    const source = { table: "legal_unit", match: { id: 1 }, column: "name" };
    const none = { dataSourceId: null, editComment: null };
    expect(await editPeriodInFrame(client, live, source, "NORDLYS AS")).toEqual({ validFrom: "2026-01-01", validTo: null, ...none });
    expect(await editPeriodInFrame(client, prev, source, "NORDLYS AS")).toEqual({ validFrom: "2025-01-01", validTo: "2025-12-31", ...none });
    expect(await editPeriodInFrame(client, y2024, source, "NORDLYS AS")).toEqual({ validFrom: "2024-01-01", validTo: "2024-12-31", ...none });
  });

  it("starts with the data source and comment of the row the edit starts in, so a save that changes neither keeps them", async () => {
    // FRAME REVIEW AS (6060606060): survey (id 2) in every year, a comment only in 2025.
    const client = fakeClient([
      { valid_from: "2023-01-01", valid_to: "2024-12-31", name: "FRAME REVIEW AS", data_source_id: 2, edit_comment: "" },
      { valid_from: "2025-01-01", valid_to: "2025-12-31", name: "FRAME REVIEW AS", data_source_id: 2, edit_comment: "checked" },
      { valid_from: "2026-01-01", valid_to: "infinity", name: "FRAME REVIEW AS", data_source_id: null, edit_comment: null },
    ]);
    const source = { table: "legal_unit", match: { id: 25 }, column: "name" };
    expect(await editPeriodInFrame(client, prev, source, "FRAME REVIEW AS")).toEqual({
      validFrom: "2025-01-01",
      validTo: "2025-12-31",
      dataSourceId: "2",
      editComment: "checked",
    });
    expect(await editPeriodInFrame(client, y2024, source, "FRAME REVIEW AS")).toEqual({
      validFrom: "2024-01-01",
      validTo: "2024-12-31",
      dataSourceId: "2",
      editComment: null,
    });
    expect(await editPeriodInFrame(client, live, source, "FRAME REVIEW AS")).toEqual({
      validFrom: "2026-01-01",
      validTo: null,
      dataSourceId: null,
      editComment: null,
    });
  });

  it("starts at the unit's birth when it was born inside the frame", async () => {
    const client = fakeClient([{ valid_from: "2025-06-15", valid_to: "infinity", name: "NYFØDT AS" }]);
    const source = { table: "legal_unit", match: { id: 2 }, column: "name" };
    expect(await editPeriodInFrame(client, prev, source, "NYFØDT AS")).toEqual({ validFrom: "2025-06-15", validTo: "2025-12-31", dataSourceId: null, editComment: null });
  });
});
