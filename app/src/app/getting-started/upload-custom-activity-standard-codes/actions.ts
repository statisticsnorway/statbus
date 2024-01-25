"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadCustomActivityCodes(formData: FormData) {
  "use server";

  try {
    const file = formData.get('custom_activity_category_codes') as File
    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/activity_category_available_custom`, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/csv'
      },
      body: file
    })

    if (!response.ok) {
      const data = await response.json()
      console.error(`failed to upload custom activity category standards with status ${response.status} ${response.statusText}`)
      console.error(data)
      return {error: data.message}
    }

  } catch (e) {
    return {error: 'failed to upload custom activity category standards'}
  }

  return redirect('/getting-started/upload-legal-units', RedirectType.push)
}
