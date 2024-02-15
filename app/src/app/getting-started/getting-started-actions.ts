"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";
import {createClient} from "@/lib/supabase/server";
import {revalidatePath} from "next/cache";

interface State {
    error: string | null
}

export type UploadView =
    "region_upload"
    | "legal_unit_region_activity_category_current"
    | "activity_category_available_custom"
    | "establishment_region_activity_category_stats_current";

export async function uploadFile(filename: string, uploadView: UploadView, _prevState: State, formData: FormData): Promise<State> {
    "use server";

    try {
        const file = formData.get(filename) as File
        const authFetch = setupAuthorizedFetchFn()
        const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/${uploadView}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'text/csv'
            },
            body: file
        })

        if (!response.ok) {
            const data = await response.json()
            console.error(`upload to ${uploadView} failed with status ${response.status} ${response.statusText}`)
            console.error(data)
            return {error: data.message.replace(/,/g, ', ').replace(/;/g, '; ')}
        }

    } catch (e) {
        return {error: `failed to upload in view ${uploadView}`}
    }

    switch (uploadView) {
        case "activity_category_available_custom":
            return redirect('/getting-started/upload-regions', RedirectType.push)
        case "region_upload":
            return redirect('/getting-started/upload-legal-units', RedirectType.push)
        case "legal_unit_region_activity_category_current":
            return redirect('/getting-started/upload-establishments', RedirectType.push)
        case "establishment_region_activity_category_stats_current":
            return redirect('/getting-started/summary', RedirectType.push)
    }
}

export async function setCategoryStandard(formData: FormData) {
    "use server";
    const client = createClient()

    const activityCategoryStandardIdFormEntry = formData.get('activity_category_standard_id')
    if (!activityCategoryStandardIdFormEntry) {
        return {error: 'No activity category standard provided'}
    }

    const activityCategoryStandardId = parseInt(activityCategoryStandardIdFormEntry.toString(), 10);
    if (isNaN(activityCategoryStandardId)) {
        return {error: 'Invalid activity category standard provided'}
    }

    try {
        const response = await client
            .from('settings')
            .upsert({activity_category_standard_id: activityCategoryStandardId}, {
                onConflict: 'only_one_setting',
            })

        if (response.status >= 400) {
            console.error('failed to configure activity category standard')
            console.error(response.error)
            return {error: response.statusText}
        }

        revalidatePath('/getting-started')

    } catch (error) {
        return {error: "Error setting category standard"}
    }

    redirect('/getting-started/upload-custom-activity-standard-codes', RedirectType.push)
}
