"use server";

import { createClient } from "@/lib/supabase/server";
import logger from "@/lib/logger";

export async function refreshStatisticalUnits() {
  "use server";
  const client = createClient();

  try {
    const { status, statusText, data, error } = await client.rpc(
      "statistical_unit_refresh_now"
    );

    if (error) {
      logger.error(
        { error },
        `statistical units refresh returned status ${statusText} and error ${error.message}`
      );
      return { error: error.message };
    }

    if (status >= 400) {
      logger.error(`statistical units refresh returned status ${statusText}`);
      return { error: statusText };
    }

    return { error: null, data };
  } catch (error) {
    return { error: "Error refreshing statistical units" };
  }
}

export async function resetAll() {
  "use server";
  const client = createClient();

  try {
    const { data, error } = await client.rpc("reset_all_data", {
      confirmed: true,
    });

    if (error) {
      logger.error(`reset all returned error ${error.message}`);
      return { error: error.message };
    }

    return { error: null, data };
  } catch (error) {
    return { error: "Error resetting establishments" };
  }
}
