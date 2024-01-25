"use server";
import {revalidatePath} from "next/cache";
import {redirect, RedirectType} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

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

