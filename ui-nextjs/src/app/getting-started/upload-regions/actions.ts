"use server";
import {createClient} from "@/app/login/supabase.server.client";
import {redirect} from "next/navigation";

export async function uploadRegions(formData: FormData) {
  "use server";
  const client = createClient()
  const file = formData.get('regions') as File
  const session = await client.auth.getSession()

  const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/region`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.data.session?.access_token}`,
      apikey: process.env.SUPABASE_ANON_KEY!,
      'Content-Type': 'text/csv'
    },
    body: file
  })

  if (response.ok) {
    redirect('/getting-started/summary')
  }

  return response.ok ? redirect('/getting-started/summary') : { error: response.statusText }
}
