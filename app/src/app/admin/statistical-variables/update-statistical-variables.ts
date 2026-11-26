"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { zfd } from "zod-form-data";
import { z } from "zod";
import { describeInvalidForm } from "@/components/form/metadata-validation";

const schema = zfd.formData({
  name: z.string().min(1, "Name is required"),
  code: z.string().min(1, "Code is required"),
  description: z.string().optional(),
  priority: z.coerce.number().int().min(1, "Priority is required"),
  enabled: zfd.checkbox(),
  type: z.enum(["int", "float", "string", "bool"], { message: "Type is required" }),
});


export async function createStatDefinition(
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = schema.safeParse(formData);

  if (!validatedFields.success) {
    return describeInvalidForm(validatedFields.error);
  }

  const { error } = await client
    .from("stat_definition")
    .insert({ ...validatedFields.data, frequency: "yearly" });

  if (error) {
    return { status: "error", message: error.message };
  }

  return {
    status: "success",
    message: "Statistical variable successfully created",
  };
}

export async function updateStatDefinition(
  id: number,
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = schema.safeParse(formData);

  if (!validatedFields.success) {
    return describeInvalidForm(validatedFields.error);
  }

  const { error } = await client
    .from("stat_definition")
    .update(validatedFields.data)
    .eq("id", id);

  if (error) {
    return { status: "error", message: error.message };
  }
  return {
    status: "success",
    message: "Statistical variable successfully updated",
  };
}
