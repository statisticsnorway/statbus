"use server";
import {createClient} from "@/lib/supabase.server.client";
import {redirect, RedirectType} from "next/navigation";

export async function uploadRegions(formData: FormData) {
  "use server";
  const client = createClient()
  const file = formData.get('regions') as File
  const session = await client.auth.getSession()

  const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/region_view`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.data.session?.access_token}`,
      apikey: process.env.SUPABASE_ANON_KEY!,
      'Content-Type': 'text/csv'
    },
    body: file
  })

  return response.ok ? redirect('/getting-started/summary', RedirectType.push) : { error: response.statusText }
}
