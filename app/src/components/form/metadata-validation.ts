import { z } from "zod";

/**
 * How an edit form's fields read what the user typed. A form sends "" for a
 * field left or made empty; the edit stores no value (NULL) for it, the same
 * as the import stores for an empty cell. An absent field (another form
 * posting to the same action) stays undefined, so the edit leaves it alone.
 */
const emptyAsNull = (val: unknown) => (typeof val === "string" && val.trim() === "" ? null : val);

/** Optional text: empty clears it. */
export const optionalText = z.preprocess(emptyAsNull, z.string().nullable().optional());

/**
 * An ISO date (YYYY-MM-DD) a user types or picks. A missing value says it is
 * required; anything else that is not a real date says so.
 */
const isoDate = z.iso.date({ error: (issue) => (issue.input === undefined ? "Required" : "Invalid date") });

/** Optional ISO date: empty clears it. */
export const optionalDate = z.preprocess(emptyAsNull, isoDate.nullable().optional());

/** Text the database requires (a unit's name): empty is refused on the field. */
export const requiredText = (message: string) =>
  z.preprocess(emptyAsNull, z.string({ error: message }).optional());

/**
 * A number the database requires when the field is posted (a statistical
 * variable's value): empty or not a number is refused on the field. Removing
 * the value altogether is removing the record (STATBUS-611).
 */
export const requiredNumber = z.preprocess(
  (val) => {
    const v = emptyAsNull(val);
    return typeof v === "string" ? Number(v) : v;
  },
  z
    .number({ error: "Enter a number" })
    .refine((n) => Number.isFinite(n), "Enter a number")
    .optional()
);

/**
 * A refused edit's response: the toast says what to fix (the fields' own
 * messages), and errors carry each message on its field.
 */
export function describeInvalidForm(error: z.ZodError): UpdateResponse {
  const errors = error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message }));
  return {
    status: "error",
    message: [...new Set(errors.map((e) => e.message))].join("; "),
    errors,
  };
}

export const editMetadataSchemaFields = {
  edit_comment: z.string().optional(),
  data_source_id: z.preprocess(
    (val) => (val === "" ? null : val),
    z.coerce.number().nullable().optional()
  ),
  valid_from: isoDate,
  valid_to: z.preprocess(
    (val) => (val === "" ? "infinity" : val),
    z.union([isoDate, z.literal("infinity")])
  ),
};

/**
 * A schema an edit form posts to: it reads the posted FormData into the edit's
 * fields, which always include the edit period (editMetadataSchemaFields). The
 * shared edit actions read valid_from and valid_to and pass the other fields on
 * to the table the form edits.
 */
export type EditSchema = z.ZodType<{ valid_from: string; valid_to: string } & Record<string, unknown>>;
