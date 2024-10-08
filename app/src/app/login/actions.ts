"use server";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/utils/supabase/server";
import { createServerLogger } from "@/lib/server-logger";

export interface LoginState {
  error: string | null;
}

export async function login(
  _prevState: LoginState,
  formData: FormData
): Promise<LoginState> {
  const email = String(formData.get("email"));
  const password = String(formData.get("password"));
  const client = await createSupabaseServerClient();

  const { error } = await client.auth.signInWithPassword({
    email,
    password,
  });

  const logger = await createServerLogger();

  if (error) {
    logger.error({ ...error, email }, `Login failed`);
    return { error: error.message };
  }

  logger.info("Login successful");

  redirect("/");
}

export async function logout() {
  const client = await createSupabaseServerClient();
  await client.auth.signOut();
  redirect("/login");
}
