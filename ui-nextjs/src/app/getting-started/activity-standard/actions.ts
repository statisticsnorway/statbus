"use server";
import {createClient} from "@/lib/supabase.server.client";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";

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
    // TODO: this should be an upsert request (separate view) but this is as of yet not implemented
    await client.from('settings').insert({activity_category_standard_id: activityCategoryStandardId})
    revalidatePath('/getting-started')
  } catch (error) {
    return {error: "Error setting category standard"}
  }

  redirect('/getting-started/upload-regions')
}

