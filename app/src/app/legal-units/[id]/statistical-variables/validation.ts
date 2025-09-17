import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const statsSchema = zfd
  .formData({
    stat_definition_id: z.coerce.number(),
    value_int: z.coerce.number().nullable().optional(),
    value_float: z.coerce.number().nullable().optional(),
    ...editMetadataSchemaFields,
  })

