import {z} from "zod";
import {zfd} from "zod-form-data";

export const formSchema = zfd.formData({
  name: z.string().min(1),
  tax_reg_ident: z.string().min(9).max(10).nullable()
})

export type FormValue = z.infer<typeof formSchema>

