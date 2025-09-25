import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const activitySchema = zfd
  .formData({
    category_id: z.coerce.number().optional(),
    ...editMetadataSchemaFields,
  })

