import { editMetadataSchemaFields, optionalText } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

/** The ways to reach a unit a contact holds; the contact table requires at least one. */
const CONTACT_WAYS = [
  "email_address",
  "phone_number",
  "web_address",
  "landline",
  "mobile_number",
  "fax_number",
] as const;

// A contact with every way emptied is no contact: the table refuses it ("One
// information must be provided"), and the edit form's Remove takes it away.
export const contactInfoSchema = zfd.formData(
  z
    .object({
      email_address: optionalText,
      phone_number: optionalText,
      web_address: optionalText,
      landline: optionalText,
      mobile_number: optionalText,
      fax_number: optionalText,
      ...editMetadataSchemaFields,
    })
    .refine((contact) => CONTACT_WAYS.some((way) => contact[way] != null), {
      message: "Enter at least one way to reach the unit, or use Remove to remove the contact",
      path: ["email_address"],
    })
);
