"use server";
import {createClient} from "@/app/auth/_lib/supabase.server.client";
import {revalidatePath} from "next/cache";

export async function setCategoryStandard(formData: FormData) {
  "use server";
  const client = createClient()
  const id = formData.get('activity_category_standard_id')
  await client.from('settings').insert({activity_category_standard_id: id})
  revalidatePath('/')
}
