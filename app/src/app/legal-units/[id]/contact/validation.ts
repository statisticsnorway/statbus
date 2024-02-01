import {z} from "zod";
import {zfd} from "zod-form-data";

export const formSchema = zfd.formData({
  email_address: z.string().email().optional().or(z.literal("")).nullable(),
  telephone_no: z.string().min(8).max(25).optional().or(z.literal("")).nullable(),
  web_address: z.string().url().optional().or(z.literal('')).nullable()
})

