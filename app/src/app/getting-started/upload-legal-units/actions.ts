"use server";
import {redirect, RedirectType} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

export async function uploadLegalUnits(formData: FormData) {
  "use server";
  const client = createClient()
  const file = formData.get('regions') as File
  const session = await client.auth.getSession()

  const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/legal_unit_region_activity_category_stats_view`, {
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
