import {createClient} from "@/lib/supabase/server";

export async function getEnterpriseById(id: string) {
  const {data: enterprises, error} = await createClient()
    .from("enterprise")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {enterprise: enterprises?.[0], error};
}

