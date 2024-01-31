import {z} from "zod";

export const schema = z.object({
  name: z.string().nullable(),
  tax_reg_ident: z.string().nullable()
})

export type FormValue = z.infer<typeof schema>
