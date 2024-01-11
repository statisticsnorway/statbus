"use server";


import {createClient} from "@/lib/supabase/server";

export async function resetRegions() {
    "use server";
    const client = createClient()

    try {
        const response = await client
            .from('region')
            .delete()
            .gt('id', 0)

        if (response.status >= 400) {
            return {error: response.statusText}
        }

    } catch (error) {
        return {error: "Error resetting regions"}
    }
}
