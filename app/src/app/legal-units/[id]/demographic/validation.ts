import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const demographicSchema = zfd.formData({
  status_id: z.coerce.number().optional(),
  birth_date: z.preprocess(
    (val) => (val === "" ? undefined : val),
    z.string().date().optional()
  ),
  death_date: z.preprocess(
    (val) => (val === "" ? undefined : val),
    z.string().date().optional()
  ),
  unit_size_id: z.preprocess(
    (val) => (val === "" ? null : val),
    z.coerce.number().nullable().optional()
  ),
  ...editMetadataSchemaFields,
});
