"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadLegalUnits(formData: FormData) {
  "use server";
  const file = formData.get('regions') as File
  const authFetch = setupAuthorizedFetchFn()
  const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/legal_unit_region_activity_category_stats_view`, {
    method: 'POST',
    headers: {
      'Content-Type': 'text/csv'
    },
    body: file
  })

  return response.ok ? redirect('/getting-started/summary', RedirectType.push) : { error: response.statusText }
}
