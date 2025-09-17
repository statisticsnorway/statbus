import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const generalInfoSchema = zfd.formData({
  name: z.string().optional(),
  status_id: z.coerce.number().optional(),
  birth_date: z.string().date().optional(),
  death_date: z.preprocess(
    (val) => (val === "" ? undefined : val),
    z.string().date().optional()
  ),
  sector_id: z.coerce.number().optional(),
  legal_form_id: z.coerce.number().optional(),
  ...editMetadataSchemaFields,
});
 

export const locationSchema = zfd.formData({
  address_part1: z.string().optional(),
  address_part2: z.string().optional(),
  address_part3: z.string().optional(),
  postcode: z.string().optional(),
  postplace: z.string().optional(),
  region_id: z.coerce.number().optional(),
  country_id: z.coerce.number().optional(),
  ...editMetadataSchemaFields,
});

