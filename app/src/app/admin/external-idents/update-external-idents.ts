"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { zfd } from "zod-form-data";
import { z } from "zod";

const base = z.object({
  name: z.string().min(1, "Name is required"),
  code: z.string().min(1, "Code is required"),
  description: z.string().optional(),
  priority: z.coerce.number().int().min(1, "Priority is required"),
  enabled: zfd.checkbox(),
});

const schema = zfd.formData(z.discriminatedUnion("shape", [
  base.extend({
    shape: z.literal("regular"),
    labels: z.string().optional(),
  }),
  base.extend({
    shape: z.literal("hierarchical"),
    labels: z.string().min(1, "Label is required for hierarchical idents"),
  }),
]));



export async function createExternalIdentType(
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = schema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "Failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { error } = await client
    .from("external_ident_type")
    .insert(validatedFields.data);

  if (error) {
    return { status: "error", message: error.message };
  }

  return {
    status: "success",
    message: "External ident type successfully created",
  };
}

export async function updateExternalIdentType(
  id: number,
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = schema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "Failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { error } = await client
    .from("external_ident_type")
    .update(validatedFields.data)
    .eq("id", id);

  if (error) {
    return { status: "error", message: error.message };
  }
  return {
    status: "success",
    message: "External ident type successfully updated",
  };
}

