import { z } from "zod";

export const editMetadataSchemaFields = {
  edit_comment: z.string().optional(),
  data_source_id: z.preprocess(
    (val) => (val === "" ? null : val),
    z.coerce.number().nullable().optional()
  ),
  valid_from: z.string().date(),
  valid_until: z.preprocess(
    (val) => (val === "" ? "infinity" : val),
    z.union([z.string().date(), z.literal("infinity")])
  ),
};
