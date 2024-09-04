import { z } from "zod";
import { zfd } from "zod-form-data";

export const generalInfoSchema = zfd.formData({
  name: z.string().min(1).nullable(),
  // tax_ident: z.string().min(9).max(10).nullable(),
});
