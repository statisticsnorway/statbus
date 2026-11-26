"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { zfd } from "zod-form-data";
import { z } from "zod";
import { describeInvalidForm } from "@/components/form/metadata-validation";

const schema = zfd.formData({
  name: z.string().min(1, "Name is required"),
  code: z.string().min(1, "Code is required"),
  enabled: zfd.checkbox(),
  description: z.string(),
  code_pattern: z.enum(["digits", "dot_after_two_digits"], { message: "Code pattern is required" }),
});

export async function updateActivityCategorySettings(
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
    .from("activity_category_standard")
    .update(validatedFields.data)
    .eq("id", id);

  if (error) {
    return { status: "error", message: error.message };
  }
  return {
    status: "success",
    message: "Activity category standard successfully updated",
  };
}
