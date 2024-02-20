import {createClient} from "@/lib/supabase/server";

export async function getEstablishmentById(id: string) {
  const {data: establishment} = await createClient()
    .from("establishment")
    .select("*")
    .eq("id", id)
    .single()

  return establishment;
}
