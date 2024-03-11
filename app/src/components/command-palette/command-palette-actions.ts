"use server";

import {createClient} from "@/lib/supabase/server";

export async function refreshStatisticalUnits() {
    "use server";
    const client = createClient()

    try {
        const {status, statusText, data, error} = await client.rpc('statistical_unit_refresh_now')

        if (error) {
            console.error(`statistical units refresh returned status ${statusText} and error ${error.message}`)
            return {error: error.message}
        }

        if (status >= 400) {
            console.error(`statistical units refresh returned status ${statusText}`)
            return {error: statusText}
        }

        return {error: null, data}

    } catch (error) {
        return {error: "Error refreshing statistical units"}
    }
}

export async function resetAll() {
    "use server";
    const client = createClient()

    try {
        // TODO: update ts definitions for supabase to include rpc - then remove ts-ignore
        // @ts-ignore
      await client.rpc('reset_all_data', { confirmed: true})
    } catch (error) {
        return {error: "Error resetting establishments"}
    }
}
