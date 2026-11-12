import { editMetadataSchemaFields, requiredNumber } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const statsSchema = zfd
  .formData({
    stat_definition_id: z.coerce.number(),
    value_int: requiredNumber,
    value_float: requiredNumber,
    ...editMetadataSchemaFields,
  })
