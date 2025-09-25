import { z } from "zod";

export const editMetadataSchemaFields = {
  edit_comment: z.string().optional(),
  data_source_id: z.preprocess(
    (val) => (val === "" ? undefined : val),
    z.coerce.number().optional()
  ),
  valid_from: z.string().date(),
  valid_until: z.preprocess(
    (val) => (val === "" ? "infinity" : val),
    z.union([z.string().date(), z.literal("infinity")])
  ),
};
