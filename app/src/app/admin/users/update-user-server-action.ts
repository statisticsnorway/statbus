"use server";
import { revalidatePath } from "next/cache";
import { getServerRestClient } from "@/context/RestClientStore";
import { zfd } from "zod-form-data";
import { z } from "zod";

const baseUserSchema = z.object({
  display_name: z.string().min(1, "Display name is required"),
  email: z.string().min(1, "Email is required").email(),
  statbus_role: z.enum(
    ["admin_user", "regular_user", "external_user", "restricted_user"],
    { message: "Role is required" }
  ),
});

const createUserSchema = zfd.formData(
  baseUserSchema.extend({
    password: z.string().min(8, "Password must contain at least 8 characters"),
  })
);

const updateUserSchema = zfd.formData(
  baseUserSchema.extend({
    id: zfd.numeric(z.number().int().positive()),
    password: z
      .string()
      .min(8, "Password must contain at least 8 characters")
      .or(z.literal("")),
  })
);

export async function createUser(
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = createUserSchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { display_name, email, statbus_role, password } = validatedFields.data;

  const { error } = await client.rpc("user_create", {
    p_display_name: display_name,
    p_email: email,
    p_statbus_role: statbus_role,
    p_password: password,
  });

  if (error) {
    return { status: "error", message: error.message };
  }

  return { status: "success", message: "User successfully created" };
}

export async function updateUser(
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = updateUserSchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { id, password, ...updatedFields } = validatedFields.data;

  const updatePayload: { [key: string]: any } = { ...updatedFields };

  if (password) {
    updatePayload.password = password;
  }

  const { error } = await client
    .from("user")
    .update(updatePayload)
    .eq("id", id);

  if (error) {
    return { status: "error", message: error.message };
  }
  return { status: "success", message: "User successfully updated" };
}
