"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadLegalUnits(formData: FormData) {
  "use server";

  try {
    const file = formData.get('regions') as File
    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/legal_unit_region_activity_category_stats_current`, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/csv'
      },
      body: file
    })

    if (!response.ok) {
      const data = await response.json()
      console.error(`legal units upload failed with status ${response.status} ${response.statusText}`)
      console.error(data)
      return {error: data.message}
    }

  } catch (e) {
    return {error: 'failed to upload legal units'}
  }

  return redirect('/getting-started/summary', RedirectType.push)
}
