import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const activitySchema = zfd.formData({
  category_id: z.coerce.number(),
  ...editMetadataSchemaFields,
});

export const sectorSchema = zfd.formData({
  sector_id: z.coerce.number().optional(),
  ...editMetadataSchemaFields,
});

export const legalFormSchema = zfd.formData({
  legal_form_id: z.coerce.number().optional(),
  ...editMetadataSchemaFields,
});
