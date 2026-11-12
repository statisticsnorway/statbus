import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { demographicSchema } from "@/app/legal-units/[id]/demographic/validation";
import { generalInfoSchema, locationSchema } from "@/app/legal-units/[id]/general-info/validation";
import { statsSchema } from "@/app/legal-units/[id]/statistical-variables/validation";

// An edit form sends "" for a field the user empties. The edit stores what the
// import stores for an empty cell: no value (NULL). A value the database must
// have (a name, a statistical variable's value) is refused with a message on
// that field instead.
const form = (fields: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
};
const period = { valid_from: "2026-01-01", valid_to: "" };
const issues = (parsed: { success: boolean; error?: { issues: { path: (string | number)[]; message: string }[] } }) =>
  parsed.success ? [] : parsed.error!.issues.map((i) => [i.path.join("."), i.message]);

describe("an emptied field on an edit form", () => {
  it("clears a contact field", () => {
    const parsed = contactInfoSchema.safeParse(
      form({ ...period, email_address: "post@example.org", phone_number: "", web_address: "", landline: "", mobile_number: "", fax_number: "" })
    );
    expect(parsed.success && parsed.data).toMatchObject({
      email_address: "post@example.org",
      phone_number: null,
      web_address: null,
      landline: null,
      mobile_number: null,
      fax_number: null,
    });
  });

  it("clears an address line", () => {
    const parsed = locationSchema.safeParse(
      form({ ...period, type: "postal", country_id: "167", address_part1: "", address_part2: "", address_part3: "", postcode: "0150", postplace: "" })
    );
    expect(parsed.success && parsed.data).toMatchObject({
      address_part1: null,
      address_part2: null,
      address_part3: null,
      postcode: "0150",
      postplace: null,
    });
  });

  it("clears a birth or death date", () => {
    const parsed = demographicSchema.safeParse(form({ ...period, status_id: "1", birth_date: "", death_date: "", unit_size_id: "2" }));
    expect(parsed.success && parsed.data).toMatchObject({ birth_date: null, death_date: null, unit_size_id: 2 });
  });

  it("keeps a typed date", () => {
    const parsed = demographicSchema.safeParse(form({ ...period, status_id: "1", birth_date: "2020-05-01", death_date: "", unit_size_id: "" }));
    expect(parsed.success && parsed.data).toMatchObject({ birth_date: "2020-05-01", death_date: null, unit_size_id: null });
  });

  it("refuses an empty statistical variable, naming the field", () => {
    const parsed = statsSchema.safeParse(form({ ...period, stat_definition_id: "1", value_int: "" }));
    expect(issues(parsed)).toEqual([["value_int", "Enter a number"]]);
  });

  it("refuses a value that is not a number", () => {
    const parsed = statsSchema.safeParse(form({ ...period, stat_definition_id: "2", value_float: "12,5x" }));
    expect(issues(parsed)).toEqual([["value_float", "Enter a number"]]);
  });

  it("stores a typed statistical variable as a number", () => {
    expect(statsSchema.safeParse(form({ ...period, stat_definition_id: "1", value_int: "0" })).data).toMatchObject({ value_int: 0 });
    expect(statsSchema.safeParse(form({ ...period, stat_definition_id: "2", value_float: "1600.5" })).data).toMatchObject({ value_float: 1600.5 });
  });

  it("refuses an empty name, naming the field", () => {
    const parsed = generalInfoSchema.safeParse(form({ ...period, name: "  " }));
    expect(issues(parsed)).toEqual([["name", "Enter a name"]]);
  });

  it("leaves the name alone when the form has none (the image form)", () => {
    const parsed = generalInfoSchema.safeParse(form({ ...period, delete_image: "true" }));
    expect(parsed.success).toBe(true);
    expect(parsed.success && "name" in parsed.data && parsed.data.name !== undefined).toBe(false);
  });
});
