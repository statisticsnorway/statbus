"use server";
import {createClient} from "@/app/login/supabase.server.client";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";

export async function setCategoryStandard(formData: FormData) {
  "use server";
  const client = createClient()
  const id = formData.get('activity_category_standard_id')
  await client.from('settings').insert({activity_category_standard_id: id})
  revalidatePath('/getting-started')
  redirect('/getting-started/upload-regions')
}

