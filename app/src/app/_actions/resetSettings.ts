"use server";


import {createClient} from "@/lib/supabase/server";

export async function resetSettings() {
    "use server";
    const client = createClient()

    try {
        const response = await client
            .from('settings')
            .delete()
            .eq('only_one_setting', true)

        if (response.status >= 400) {
            return {error: response.statusText}
        }

    } catch (error) {
        return {error: "Error resetting settings"}
    }
}
