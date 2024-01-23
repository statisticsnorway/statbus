"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";

export async function uploadRegions(formData: FormData) {
    "use server";
    const file = formData.get('regions') as File

    const authFetch = setupAuthorizedFetchFn()
    const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/region_view`, {
        method: 'POST',
        headers: {
            'Content-Type': 'text/csv'
        },
        body: file
    })

    return response.ok ? redirect('/getting-started/upload-legal-units', RedirectType.push) : {error: response.statusText}
}
