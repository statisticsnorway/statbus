"use server";
import {createClient} from "@/lib/supabase/server";
import {FormValue, schema} from "@/app/legal-units/[id]/general-info/validation";
import {revalidatePath} from "next/cache";

export async function updateGeneralInfo(formValue: FormValue) {
  "use server";
  const client = createClient()

  try {
    const data = schema.parse(formValue)

    const response = await client
      .from('legal_unit')
      .update(data)
      .eq('tax_reg_ident', data.tax_reg_ident!!)

    if (response.status >= 400) {
      console.error('failed to update legal unit general info')
      console.error(response.error)
      return {error: response.statusText}
    }

    revalidatePath("/legal-units/[id]/general-info", "page")

  } catch (error) {
    console.error('failed to update legal unit general info', error)
    return {error}
  }

  return {error: null}
}

