"use server";
import {redirect, RedirectType} from "next/navigation";
import {setupAuthorizedFetchFn} from "@/lib/supabase/request-helper";
import {createClient} from "@/lib/supabase/server";
import {revalidatePath} from "next/cache";

interface State {
    error: string | null
}

export async function uploadRegions(_prevState: State, formData: FormData): Promise<State> {
    "use server";

    try {
        const file = formData.get('regions') as File
        const authFetch = setupAuthorizedFetchFn()
        const response = await authFetch(`${process.env.SUPABASE_URL}/rest/v1/region_upload`, {
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

export async function uploadLegalUnits(_prevState: State, formData: FormData): Promise<State> {
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

export async function uploadCustomActivityCodes(_prevState: State, formData: FormData): Promise<State> {
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

    redirect('/getting-started/upload-regions', RedirectType.push)
}
