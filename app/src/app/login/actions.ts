'use server'
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

export interface LoginState {
  error: string | null
}

export async function login(_prevState: LoginState, formData: FormData): Promise<LoginState> {
  const email = String(formData.get('email'))
  const password = String(formData.get('password'))
  const supabaseClient = createClient()

  const {error} = await supabaseClient.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    return {error: error.message}
  }

  redirect("/")
}

export async function logout() {
  const supabaseClient = createClient()
  await supabaseClient.auth.signOut()
  redirect("/login")
}
