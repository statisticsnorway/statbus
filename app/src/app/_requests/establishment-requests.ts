import {createClient} from "@/lib/supabase/server";

export async function getEstablishmentById(id: string) {
  const {data: establishments, error} = await createClient()
    .from("establishment")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {establishment: establishments?.[0], error};
}
