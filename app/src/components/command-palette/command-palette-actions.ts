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

export async function resetUnits() {
    "use server";
    const client = createClient()

    try {
        await client.from('activity')
            .delete()
            .gt('id', 0)

        await client.from('location')
            .delete()
            .gt('id', 0)

        await client.from('stat_for_unit')
            .delete()
            .gt('id', 0)

        await client
            .from('legal_unit')
            .delete()
            .gt('id', 0)

        await client
            .from('establishment')
            .delete()
            .gt('id', 0)

    } catch (error) {
        return {error: "Error resetting establishments"}
    }
}

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
