import { editMetadataSchemaFields } from "@/components/form/metadata-validation";
import { z } from "zod";
import { zfd } from "zod-form-data";

// Custom schema that handles empty file inputs gracefully
// When no file is selected, browser sends an empty File with size=0
const optionalFileSchema = z.any().transform((val) => {
  if (val instanceof File && val.size > 0) {
    return val as File;
  }
  return undefined;
}).optional();

export const generalInfoSchema = zfd.formData({
  name: z.string().optional(),
  image: optionalFileSchema,
  delete_image: z.string().optional(),
  ...editMetadataSchemaFields,
});

// A form field the user leaves empty arrives as "". An optional number reads it
// as no value (null); z.coerce.number() alone would turn it into 0, which the
// database reads as a reference to row 0 (STATBUS-604).
const optionalNumber = z.preprocess(
  (val) => (val === "" || val === undefined ? null : val),
  z.coerce.number().nullable()
);

export const locationSchema = zfd.formData({
  address_part1: z.string().optional(),
  address_part2: z.string().optional(),
  address_part3: z.string().optional(),
  postcode: z.string().optional(),
  postplace: z.string().optional(),
  region_id: optionalNumber,
  country_id: z.preprocess(
    (val) => (val === "" || val === undefined ? undefined : Number(val)),
    z.number({
      required_error: "Select a country",
      invalid_type_error: "Select a country",
    })
  ),
  latitude: optionalNumber,
  longitude: optionalNumber,
  altitude: optionalNumber,
  type: z.enum(["physical", "postal"]),
  ...editMetadataSchemaFields,
});

