"use server";

import {createClient} from "@/lib/supabase/server";

export async function refreshStatisticalUnits() {
  "use server";
  const client = createClient()

  try {
    const {status, statusText} = await client.rpc('statistical_unit_refresh_now')

    if (status >= 400) {
      return {error: statusText}
    }

  } catch (error) {
    return {error: "Error refreshing statistical units"}
  }
}

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
