"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
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
  const supabaseClient = createClient();

  const { error } = await supabaseClient.auth.signInWithPassword({
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
  const supabaseClient = createClient();
  await supabaseClient.auth.signOut();
  redirect("/login");
}
