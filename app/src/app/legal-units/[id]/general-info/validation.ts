import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

export const generalInfoSchema = zfd.formData({
  name: z.string().optional(),
  ...editMetadataSchemaFields,
});

export const locationSchema = zfd.formData({
  address_part1: z.string().optional(),
  address_part2: z.string().optional(),
  address_part3: z.string().optional(),
  postcode: z.string().optional(),
  postplace: z.string().optional(),
  region_id: z.coerce.number().optional(),
  country_id: z.coerce.number(),
  latitude: z.coerce.number().optional(),
  longitude: z.coerce.number().optional(),
  altitude: z.coerce.number().optional(),
  type: z.enum(["physical", "postal"]),
  ...editMetadataSchemaFields,
});

