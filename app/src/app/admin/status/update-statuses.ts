"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { zfd } from "zod-form-data";
import { z } from "zod";

const schema = zfd.formData({
  name: z.string().min(1, "Name is required"),
  code: z.string().min(1, "Code is required"),
  enabled: zfd.checkbox(),
  assigned_by_default: zfd.checkbox(),
  used_for_counting: zfd.checkbox(),
  priority: z.coerce.number().int().min(1, "Priority is required"),
});



export async function createStatusCode(
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
    .from("status")
    .insert({ custom: true, ...validatedFields.data });

  if (error) {
    return { status: "error", message: error.message };
  }

  return { status: "success", message: "Status successfully created" };
}

export async function updateStatusCode(
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
    .from("status")
    .update(validatedFields.data)
    .eq("id", id);

  if (error) {
    return { status: "error", message: error.message };
  }
  return {
    status: "success",
    message: "Status successfully updated",
  };
}
