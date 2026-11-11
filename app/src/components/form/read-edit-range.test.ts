import { readEditRange } from "@/components/form/read-edit-range";

// STATBUS-604: when an edit starts, the form reads the field's rows for the unit
// and opens the edit on the stretch where the shown value is valid, bounded by
// the selected time frame.
type Row = Record<string, unknown>;

function fakeClient(rows: Row[], record: { calls: unknown[] }) {
  const builder = {
    select(cols: string) { record.calls.push(["select", cols]); return builder; },
    eq(col: string, val: unknown) { record.calls.push(["eq", col, val]); return builder; },
    order(col: string) { record.calls.push(["order", col]); return Promise.resolve({ data: rows, error: null }); },
  };
  return { from(table: string) { record.calls.push(["from", table]); return builder; } };
}

describe("readEditRange", () => {
  it("reads the field's rows for the unit and bounds the shown value's stretch by the context", async () => {
    const record = { calls: [] as unknown[] };
    const client = fakeClient(
      [{ valid_from: "2026-11-07", valid_to: "infinity", name: "0001 INVEST AS" }],
      record
    );
    const range = await readEditRange(client as never, {
      table: "legal_unit",
      match: { id: 314286 },
      column: "name",
      shownValue: "0001 INVEST AS",
      context: { valid_from: "2026-01-01", valid_to: "2026-12-31" },
    });
    expect(range).toEqual({ validFrom: "2026-11-07", validTo: "2026-12-31", dataSourceId: null, editComment: null });
    expect(record.calls).toEqual([
      ["from", "legal_unit"],
      ["select", "valid_from,valid_to,data_source_id,edit_comment,name"],
      ["eq", "id", 314286],
      ["order", "valid_from"],
    ]);
  });

  it("matches on several keys, e.g. a unit's physical location", async () => {
    const record = { calls: [] as unknown[] };
    const client = fakeClient(
      [
        { valid_from: "2013-01-01", valid_to: "2026-05-31", address_part1: "Old road 1" },
        { valid_from: "2026-06-01", valid_to: "infinity", address_part1: "Testveien 604" },
      ],
      record
    );
    const range = await readEditRange(client as never, {
      table: "location",
      match: { legal_unit_id: 7, type: "physical" },
      column: "address_part1",
      shownValue: "Testveien 604",
      context: { valid_from: "2026-01-01", valid_to: "infinity" },
    });
    expect(range).toEqual({ validFrom: "2026-06-01", validTo: "infinity", dataSourceId: null, editComment: null });
    expect(record.calls).toContainEqual(["eq", "type", "physical"]);
  });

  it("treats a field group's columns as one value: the stretch where the whole address is unchanged", async () => {
    const record = { calls: [] as unknown[] };
    const client = fakeClient(
      [
        { valid_from: "2020-01-01", valid_to: "2026-03-31", address_part1: "Vei 1", postcode: "0001" },
        { valid_from: "2026-04-01", valid_to: "infinity", address_part1: "Vei 1", postcode: "0002" },
      ],
      record
    );
    const range = await readEditRange(client as never, {
      table: "location",
      match: { legal_unit_id: 7, type: "physical" },
      column: ["address_part1", "postcode"],
      shownValue: { address_part1: "Vei 1", postcode: "0002" },
      context: { valid_from: "2026-01-01", valid_to: "2026-12-31" },
    });
    expect(range).toEqual({ validFrom: "2026-04-01", validTo: "2026-12-31", dataSourceId: null, editComment: null });
    expect(record.calls).toContainEqual(["select", "valid_from,valid_to,data_source_id,edit_comment,address_part1,postcode"]);
  });

  it("falls back to the selected context when the read fails", async () => {
    const client = {
      from: () => ({
        select: () => ({ eq: () => ({ order: () => Promise.resolve({ data: null, error: { message: "boom" } }) }) }),
      }),
    };
    const range = await readEditRange(client as never, {
      table: "legal_unit",
      match: { id: 1 },
      column: "name",
      shownValue: "X",
      context: { valid_from: "2026-01-01", valid_to: "2026-12-31" },
    });
    expect(range).toEqual({ validFrom: "2026-01-01", validTo: "2026-12-31" });
  });
});
