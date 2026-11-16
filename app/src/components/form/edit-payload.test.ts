import {
  DIFFERS,
  editFormForValidation,
  editStartFields,
  keptColumns,
  updatePayload,
  type EditStart,
} from "./edit-payload";

// A save over ticked periods writes only what the user set (owner 2026-11-16):
// legal unit 29's Sector was 4500 in 2024-2025 and none from 2026, with data
// sources survey and nlr; ticking all three and saving must leave both alone
// unless the user sets them.
const form = (fields: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.set(k, v);
  return f;
};
const untouched = { dataSource: false, comment: false };
const agreeing: EditStart = {
  values: { sector_id: 57, legal_form_id: 1 },
  differing: [],
};
const differing: EditStart = {
  values: { sector_id: null, legal_form_id: 1 },
  differing: ["sector_id"],
};

describe("keptColumns", () => {
  it("keeps every column the user left alone", () => {
    expect(
      keptColumns(
        form({ sector_id: "57", legal_form_id: "1" }),
        agreeing,
        untouched
      )
    ).toEqual(["sector_id", "legal_form_id", "data_source_id", "edit_comment"]);
  });

  it("writes a field the user changed, and the data source and comment the user set", () => {
    expect(
      keptColumns(form({ sector_id: "", legal_form_id: "1" }), agreeing, {
        dataSource: true,
        comment: true,
      })
    ).toEqual(["legal_form_id"]);
  });

  it("keeps a field that still shows Differs", () => {
    expect(
      keptColumns(
        form({ sector_id: DIFFERS, legal_form_id: "1" }),
        differing,
        untouched
      )
    ).toContain("sector_id");
  });

  it("writes a differing field once the user chose a value, even none", () => {
    expect(
      keptColumns(
        form({ sector_id: "", legal_form_id: "1" }),
        differing,
        untouched
      )
    ).not.toContain("sector_id");
  });
});

describe("editFormForValidation", () => {
  const posted = (
    fields: Record<string, string>,
    start: EditStart,
    chosen = untouched
  ) => form({ ...fields, ...editStartFields(start, chosen) });

  it("keeps the untouched columns and validates a field showing Differs with its start value", () => {
    const { form: validated, kept } = editFormForValidation(
      posted(
        {
          sector_id: DIFFERS,
          legal_form_id: "1",
          data_source_id: "",
          edit_comment: "",
        },
        differing
      )
    );
    expect(kept).toEqual([
      "sector_id",
      "legal_form_id",
      "data_source_id",
      "edit_comment",
    ]);
    expect(validated.get("sector_id")).toBe("");
  });

  it("writes what the user set: a chosen sector and data source", () => {
    const { kept } = editFormForValidation(
      posted(
        {
          sector_id: "57",
          legal_form_id: "1",
          data_source_id: "4",
          edit_comment: "",
        },
        differing,
        {
          dataSource: true,
          comment: false,
        }
      )
    );
    expect(kept).toEqual(["legal_form_id", "edit_comment"]);
  });

  it("writes every field of a form without a start (a new record)", () => {
    const plain = form({ sector_id: "57" });
    expect(editFormForValidation(plain)).toEqual({ form: plain, kept: null });
  });
});

describe("updatePayload", () => {
  const validated = {
    valid_from: "2024-01-01",
    valid_to: "infinity",
    sector_id: null,
    legal_form_id: 1,
    data_source_id: null,
    edit_comment: "",
  };

  it("leaves out the kept columns and writes the period and the rest", () => {
    expect(
      updatePayload(validated, ["sector_id", "data_source_id", "edit_comment"])
    ).toEqual({
      valid_from: "2024-01-01",
      valid_to: "infinity",
      legal_form_id: 1,
    });
  });

  it("always writes the period", () => {
    expect(
      updatePayload(validated, [
        "valid_from",
        "valid_to",
        "sector_id",
        "legal_form_id",
        "data_source_id",
        "edit_comment",
      ])
    ).toEqual({
      valid_from: "2024-01-01",
      valid_to: "infinity",
    });
  });

  it("writes every field when nothing is kept (a new record)", () => {
    expect(updatePayload(validated, null)).toEqual(validated);
  });
});
