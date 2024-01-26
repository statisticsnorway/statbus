"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadRegions(_prevState: { error: string | null }, formData: FormData) {
  "use server";

  try {
    const file = formData.get('regions') as File
    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/region_view`, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/csv'
      },
      body: file
    })

    if (!response.ok) {
      const data = await response.json()
      console.error(`regions upload failed with status ${response.status} ${response.statusText}`)
      console.error(data)
      return {error: data.message.replace(/,/g, ', ')}
    }

  } catch (e) {
    return {error: 'failed to upload regions'}
  }

  return redirect('/getting-started/upload-custom-activity-standard-codes', RedirectType.push)
}
