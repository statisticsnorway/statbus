"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";

import { createServerLogger } from "@/lib/server-logger";
export async function setSettings(formData: FormData) {
  "use server";
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  const activityCategoryStandardIdFormEntry = formData.get(
    "activity_category_standard_id"
  );
  const countryIdFormEntry = formData.get("country_id");

  if (!activityCategoryStandardIdFormEntry) {
    return { error: "No activity category standard provided" };
  }

  const activityCategoryStandardId = parseInt(
    activityCategoryStandardIdFormEntry.toString(),
    10
  );

  if (isNaN(activityCategoryStandardId)) {
    return { error: "Invalid activity category standard provided" };
  }

  if (!countryIdFormEntry) {
    return {
      error:
        "No country provided, you need to select your country before setting the actitivy category standard.",
    };
  }

  const countryId = parseInt(countryIdFormEntry.toString(), 10);

  if (isNaN(countryId)) {
    return { error: "Invalid country provided" };
  }

  try {
    // region_version_id is required — use form value if provided, else fetch the initial one
    const regionVersionIdFormEntry = formData.get("region_version_id");
    let regionVersionId: number;
    if (regionVersionIdFormEntry) {
      regionVersionId = parseInt(regionVersionIdFormEntry.toString(), 10);
      if (isNaN(regionVersionId)) {
        return { error: "Invalid region version provided" };
      }
    } else {
      const { data: rv, error: rvError } = await client
        .from("region_version")
        .select("id")
        .eq("code", "initial")
        .limit(1)
        .single();
      if (rvError || !rv) {
        return { error: "Could not find initial region version" };
      }
      regionVersionId = rv.id;
    }

    const response = await client.from("settings").upsert(
      {
        activity_category_standard_id: activityCategoryStandardId,
        country_id: countryId,
        region_version_id: regionVersionId,
      },
      {
        onConflict: "only_one_setting",
      }
    );

    if (response.status >= 400) {
      logger.error(
        response.error,
        "failed to configure activity category standard and country"
      );
      return { error: response.statusText };
    }

    revalidatePath("/getting-started");
    return { error: null, success: true };
  } catch (error) {
    return { error: "Error setting category standard and country" };
  }
}
