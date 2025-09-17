import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const contactInfoSchema = zfd.formData({
  email_address: z.string().optional(),
  phone_number: z.string().optional(),
  web_address: z.string().optional(),
  landline: z.string().optional(),
  mobile_number: z.string().optional(),
  fax_number: z.string().optional(),
  ...editMetadataSchemaFields,
});
