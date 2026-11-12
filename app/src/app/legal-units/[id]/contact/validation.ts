import { editMetadataSchemaFields, optionalText } from "@/components/form/metadata-validation";
import { zfd } from "zod-form-data";

export const contactInfoSchema = zfd.formData({
  email_address: optionalText,
  phone_number: optionalText,
  web_address: optionalText,
  landline: optionalText,
  mobile_number: optionalText,
  fax_number: optionalText,
  ...editMetadataSchemaFields,
});
