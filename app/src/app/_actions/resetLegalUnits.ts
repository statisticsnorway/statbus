"use server";


import {createClient} from "@/lib/supabase/server";

export async function resetLegalUnits() {
  "use server";
  const client = createClient()

  try {
    const response = await client
      .from('legal_unit')
      .delete()
      .gt('id', 0)

    if (response.status >= 400) {
      console.error('failed to reset legal units', response.error)
      return {error: response.statusText}
    }

  } catch (error) {
    return {error: "Error resetting legal units"}
  }
}
