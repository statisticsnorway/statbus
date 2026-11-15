// What each edit and admin form accepts, what it writes, and how it refuses: the contract of the
// schemas the forms post to (STATBUS-630). The admin schemas live in their server actions, so the
// actions run here with a REST client that records what they would write instead of writing it.
import { activitySchema, legalFormSchema, sectorSchema } from "@/app/legal-units/[id]/classifications/validation";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { demographicSchema } from "@/app/legal-units/[id]/demographic/validation";
import { generalInfoSchema, locationSchema } from "@/app/legal-units/[id]/general-info/validation";
import { statsSchema } from "@/app/legal-units/[id]/statistical-variables/validation";

type Written = { table?: string; rpc?: string; op: string; payload: unknown; eq?: [string, unknown] };
const written: Written[] = [];
const builder = (table: string) => ({
  insert: (payload: unknown) => {
    written.push({ table, op: "insert", payload });
    return Promise.resolve({ error: null });
  },
  update: (payload: unknown) => ({
    eq: (column: string, value: unknown) => {
      written.push({ table, op: "update", payload, eq: [column, value] });
      return Promise.resolve({ error: null });
    },
  }),
});
jest.mock("@/context/RestClientStore", () => ({
  getServerRestClient: async () => ({
    from: (table: string) => builder(table),
    rpc: (rpc: string, payload: unknown) => {
      written.push({ rpc, op: "rpc", payload });
      return Promise.resolve({ error: null });
    },
  }),
}));
jest.mock("next/cache", () => ({ revalidatePath: () => undefined }));

import { createDataSource } from "@/app/admin/data-sources/update-data-sources";
import { createExternalIdentType } from "@/app/admin/external-idents/update-external-idents";
import { createStatDefinition } from "@/app/admin/statistical-variables/update-statistical-variables";
import { createStatusCode } from "@/app/admin/status/update-statuses";
import { createUnitSize } from "@/app/admin/unit-size/update-unit-sizes";
import { updateActivityCategorySettings } from "@/app/admin/activity-category-settings/update-activity-category-settings";
import { createUser, updateUser } from "@/app/admin/users/update-user-server-action";

const form = (fields: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
};
type Parsed = { success: boolean; data?: unknown; error?: { issues: { path: PropertyKey[]; message: string }[] } };
const issues = (parsed: Parsed) =>
  parsed.success ? [] : parsed.error!.issues.map((i) => [i.path.join("."), i.message]);
const period = { valid_from: "2026-01-01", valid_to: "" };

beforeEach(() => {
  written.length = 0;
});

describe("the edit period every legal unit edit carries", () => {
  it("reads an empty end as open-ended and a data source as its id", () => {
    const parsed = sectorSchema.safeParse(form({ ...period, sector_id: "3", data_source_id: "2", edit_comment: "fix" }));
    expect(parsed.success && parsed.data).toEqual({
      sector_id: 3,
      data_source_id: 2,
      edit_comment: "fix",
      valid_from: "2026-01-01",
      valid_to: "infinity",
    });
  });

  it("reads an empty data source as none", () => {
    const parsed = legalFormSchema.safeParse(form({ ...period, legal_form_id: "4", data_source_id: "" }));
    expect(parsed.success && parsed.data).toMatchObject({ legal_form_id: 4, data_source_id: null });
  });

  it("refuses a start or end that is not a date", () => {
    expect(issues(sectorSchema.safeParse(form({ valid_from: "2026-13-01", valid_to: "soon", sector_id: "3" })))).toEqual([
      ["valid_from", "Invalid date"],
      ["valid_to", "Invalid date"],
    ]);
  });

  it("refuses an edit without a start", () => {
    expect(issues(sectorSchema.safeParse(form({ valid_to: "", sector_id: "3" })))).toEqual([["valid_from", "Required"]]);
  });
});

describe("legal unit edit forms", () => {
  it("activity: a category and one of the activity types", () => {
    expect(activitySchema.safeParse(form({ ...period, category_id: "12", type: "secondary" })).data).toMatchObject({
      category_id: 12,
      type: "secondary",
    });
    expect(issues(activitySchema.safeParse(form({ ...period, category_id: "12", type: "tertiary" })))).toEqual([
      ["type", 'Invalid option: expected one of "primary"|"secondary"|"ancilliary"'],
    ]);
  });

  it("general info: a name, and no image when the browser sends an empty file", () => {
    const fd = form({ ...period, name: "Kran AS" });
    fd.append("image", new File([], ""));
    const parsed = generalInfoSchema.safeParse(fd);
    expect(parsed.success && parsed.data).toMatchObject({ name: "Kran AS", image: undefined });
  });

  it("general info: a chosen image is kept as the file", () => {
    const fd = form({ ...period, name: "Kran AS" });
    const image = new File(["png"], "logo.png", { type: "image/png" });
    fd.append("image", image);
    const parsed = generalInfoSchema.safeParse(fd);
    expect(parsed.success && (parsed.data as { image: File }).image.name).toBe("logo.png");
  });

  it("location: a non-numeric coordinate is refused on its field", () => {
    expect(issues(locationSchema.safeParse(form({ ...period, type: "physical", country_id: "167", latitude: "north" })))).toEqual([
      ["latitude", "Enter a number"],
    ]);
  });

  it("location: a type outside physical and postal is refused", () => {
    expect(issues(locationSchema.safeParse(form({ ...period, type: "visiting", country_id: "167" })))).toEqual([
      ["type", 'Invalid option: expected one of "physical"|"postal"'],
    ]);
  });

  it("contact: an absent field stays absent, so the edit leaves it alone", () => {
    const parsed = contactInfoSchema.safeParse(form({ ...period, email_address: "post@example.org" }));
    expect(parsed.success && parsed.data).toEqual({
      email_address: "post@example.org",
      valid_from: "2026-01-01",
      valid_to: "infinity",
    });
  });

  it("demographic: a date that is not a date is refused on its field", () => {
    expect(issues(demographicSchema.safeParse(form({ ...period, birth_date: "2020-02-30" })))).toEqual([
      ["birth_date", "Invalid date"],
    ]);
  });

  it("statistical variable: a number is read as a number", () => {
    expect(statsSchema.safeParse(form({ ...period, stat_definition_id: "1", value_int: "42" })).data).toMatchObject({
      stat_definition_id: 1,
      value_int: 42,
    });
  });

  it("statistical variable: text where a number belongs is refused on the field", () => {
    expect(issues(statsSchema.safeParse(form({ ...period, stat_definition_id: "1", value_float: "many" })))).toEqual([
      ["value_float", "Enter a number"],
    ]);
  });
});

describe("admin forms", () => {
  const refused = (fields: [string, string][], message = "Failed to parse form data") => ({
    status: "error",
    message,
    errors: fields.map(([path, message]) => ({ path, message })),
  });

  it("data source: written with the checkbox as a boolean", async () => {
    expect(await createDataSource(null, form({ name: "Survey", code: "survey", enabled: "on" }))).toMatchObject({ status: "success" });
    expect(written).toEqual([
      { table: "data_source", op: "insert", payload: { custom: true, name: "Survey", code: "survey", enabled: true } },
    ]);
  });

  it("data source: an unticked checkbox is false, and empty name and code are refused", async () => {
    expect(await createDataSource(null, form({ name: "", code: "" }))).toEqual(
      refused([["name", "Name is required"], ["code", "Code is required"]])
    );
    expect(written).toEqual([]);
    await createDataSource(null, form({ name: "Survey", code: "survey" }));
    expect(written[0].payload).toMatchObject({ enabled: false });
  });

  it("unit size: name, code and enabled", async () => {
    await createUnitSize(null, form({ name: "Small", code: "small", enabled: "on" }));
    expect(written).toEqual([
      { table: "unit_size", op: "insert", payload: { custom: true, name: "Small", code: "small", enabled: true } },
    ]);
  });

  it("status: three checkboxes and a priority from 1", async () => {
    await createStatusCode(null, form({ name: "Active", code: "active", enabled: "on", used_for_counting: "on", priority: "2" }));
    expect(written).toEqual([
      {
        table: "status",
        op: "insert",
        payload: { custom: true, name: "Active", code: "active", enabled: true, assigned_by_default: false, used_for_counting: true, priority: 2 },
      },
    ]);
    expect(await createStatusCode(null, form({ name: "Active", code: "active", priority: "0" }))).toEqual(
      refused([["priority", "Priority is required"]])
    );
  });

  it("statistical variable definition: one of the four types", async () => {
    await createStatDefinition(null, form({ name: "Employees", code: "employees", priority: "1", enabled: "on", type: "int" }));
    expect(written[0]).toMatchObject({
      table: "stat_definition",
      op: "insert",
      payload: { name: "Employees", code: "employees", priority: 1, enabled: true, type: "int" },
    });
    expect(await createStatDefinition(null, form({ name: "E", code: "e", priority: "1", type: "date" }))).toEqual(
      refused([["type", 'Invalid option: expected one of "int"|"float"|"string"|"bool"']])
    );
  });

  it("external ident type: a hierarchical one needs labels, a regular one does not", async () => {
    const base = { name: "Census", code: "census", priority: "3", enabled: "on" };
    await createExternalIdentType(null, form({ ...base, shape: "regular" }));
    expect(written[0]).toMatchObject({
      table: "external_ident_type",
      op: "insert",
      payload: { name: "Census", code: "census", priority: 3, enabled: true, shape: "regular" },
    });
    expect(await createExternalIdentType(null, form({ ...base, shape: "hierarchical", labels: "" }))).toEqual(
      refused([["labels", "Label is required for hierarchical idents"]])
    );
    expect(await createExternalIdentType(null, form({ ...base, shape: "ring" }))).toEqual(
      refused([["shape", "Invalid discriminator value. Expected 'regular' | 'hierarchical'"]])
    );
  });

  it("activity category standard: a code pattern from the two", async () => {
    await updateActivityCategorySettings(
      7,
      null,
      form({ name: "NACE", code: "nace", description: "EU", code_pattern: "digits", enabled: "on" })
    );
    expect(written).toEqual([
      {
        table: "activity_category_standard",
        op: "update",
        payload: { name: "NACE", code: "nace", description: "EU", code_pattern: "digits", enabled: true },
        eq: ["id", 7],
      },
    ]);
  });

  it("user: created with role and password; refused with a short password and a bad address", async () => {
    await createUser(null, form({ display_name: "Ada", email: "ada@example.org", statbus_role: "regular_user", password: "longenough" }));
    expect(written).toEqual([
      {
        rpc: "user_create",
        op: "rpc",
        payload: expect.objectContaining({ p_display_name: "Ada", p_email: "ada@example.org", p_statbus_role: "regular_user", p_password: "longenough" }),
      },
    ]);
    expect(await createUser(null, form({ display_name: "Ada", email: "ada", statbus_role: "boss", password: "short" }))).toEqual(
      refused([
        ["email", "Invalid email"],
        ["statbus_role", "Role is required"],
        ["password", "Password must contain at least 8 characters"],
      ], "failed to parse form data")
    );
  });

  it("user: an update keeps the password when it is left empty", async () => {
    await updateUser(null, form({ id: "5", display_name: "Ada", email: "ada@example.org", statbus_role: "admin_user", password: "" }));
    expect(written).toEqual([
      { table: "user", op: "update", payload: { display_name: "Ada", email: "ada@example.org", statbus_role: "admin_user" }, eq: ["id", 5] },
    ]);
  });
});
