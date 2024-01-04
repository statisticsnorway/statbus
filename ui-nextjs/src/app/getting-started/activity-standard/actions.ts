"use server";
import {createClient} from "@/app/login/supabase.server.client";
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
    await client.from('settings').insert({activity_category_standard_id: activityCategoryStandardId})
    revalidatePath('/getting-started')
  } catch (error) {
    return {error: "Error setting category standard"}
  }

  redirect('/getting-started/upload-regions')
}

