'use server'
import {createClient} from "@/lib/supabase.server.client";
import {redirect} from "next/navigation";

export async function login(formData: FormData) {
  const email = String(formData.get('email'))
  const password = String(formData.get('password'))
  const supabaseClient = createClient()

  const {error} = await supabaseClient.auth.signInWithPassword({
    email,
    password,
  })

  if (!error) {
    redirect("/")
  }
}

export async function logout() {
  const supabaseClient = createClient()
  await supabaseClient.auth.signOut()
  redirect("/login")
}
