import { describeInvalidForm } from "@/components/form/metadata-validation";
import { statsSchema } from "@/app/legal-units/[id]/statistical-variables/validation";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";

// A refused edit tells the user what to fix: the toast shows the field's own
// message, and the errors carry it per field for forms that show it in place.
const form = (fields: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
};
const period = { valid_from: "2026-01-01", valid_to: "" };

describe("describeInvalidForm", () => {
  it("says what to fix in an emptied statistical variable", () => {
    const parsed = statsSchema.safeParse(form({ ...period, stat_definition_id: "1", value_int: "" }));
    expect(!parsed.success && describeInvalidForm(parsed.error)).toEqual({
      status: "error",
      message: "Enter a number",
      errors: [{ path: "value_int", message: "Enter a number" }],
    });
  });

  // The contact table holds at least one way to reach the unit
  // ("One information must be provided"); a contact with none is removed instead.
  it("points an emptied contact to Remove", () => {
    const parsed = contactInfoSchema.safeParse(form({ ...period, email_address: "", phone_number: "" }));
    expect(!parsed.success && describeInvalidForm(parsed.error)).toEqual({
      status: "error",
      message: "Enter at least one way to reach the unit, or use Remove to remove the contact",
      errors: [
        {
          path: "email_address",
          message: "Enter at least one way to reach the unit, or use Remove to remove the contact",
        },
      ],
    });
  });

  it("says what to fix in an emptied name", () => {
    const parsed = generalInfoSchema.safeParse(form({ ...period, name: "" }));
    expect(!parsed.success && describeInvalidForm(parsed.error)).toEqual({
      status: "error",
      message: "Enter a name",
      errors: [{ path: "name", message: "Enter a name" }],
    });
  });
});
