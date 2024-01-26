"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadLegalUnits(_prevState: { error: string | null }, formData: FormData) {
  "use server";

  try {
    const file = formData.get('legal_units') as File
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
      return {error: data.message.replace(/,/g, ', ')}
    }

  } catch (e) {
    return {error: 'failed to upload legal units'}
  }

  return redirect('/getting-started/summary', RedirectType.push)
}
