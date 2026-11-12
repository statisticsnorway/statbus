import { editMetadataSchemaFields, optionalDate } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const demographicSchema = zfd.formData({
  status_id: z.coerce.number().optional(),
  birth_date: optionalDate,
  death_date: optionalDate,
  unit_size_id: z.preprocess(
    (val) => (val === "" ? null : val),
    z.coerce.number().nullable().optional()
  ),
  ...editMetadataSchemaFields,
});
