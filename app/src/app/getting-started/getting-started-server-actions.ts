"use server";
import { getServerRestClient, fetchWithAuthRefresh } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";

import { createServerLogger } from "@/lib/server-logger";

interface State {
  readonly error: string | null;
  readonly success?: boolean;
}

export type UploadView =
  | "region_upload"
  | "import_legal_unit_current"
  | "activity_category_available_custom"
  | "import_establishment_current_for_legal_unit"
  | "import_establishment_current_without_legal_unit"
  | "sector_custom_only"
  | "legal_form_custom_only";

export async function uploadFile(
  filename: string,
  uploadView: UploadView,
  _prevState: State,
  formData: FormData
): Promise<State> {
  "use server";

  try {
    const logger = await createServerLogger();
    const file = formData.get(filename) as File;
    const client = await getServerRestClient();

    // Get the base URL from the client
    const postgrestUrl = client.url;
    
    // We need to use the full URL here because uploadView is a view name, not a relative path
    const response = await fetchWithAuthRefresh(
      `${postgrestUrl}/${uploadView}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "text/csv",
        },
        body: file,
      }
    );
    if (!response.ok) {
      const data = await response.json();
      logger.error(
        { data },
        `upload to ${uploadView} failed with status ${response.status} ${response.statusText}`
      );
      return { error: data.message.replace(/,/g, ", ").replace(/;/g, "; ") };
    }

    return { error: null, success: true };
  } catch (e) {
    return { error: `failed to upload in view ${uploadView}` };
  }
}

export async function setCategoryStandard(formData: FormData) {
  "use server";
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  const activityCategoryStandardIdFormEntry = formData.get(
    "activity_category_standard_id"
  );
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

  try {
    const response = await client.from("settings").upsert(
      { activity_category_standard_id: activityCategoryStandardId },
      {
        onConflict: "only_one_setting",
      }
    );

    if (response.status >= 400) {
      logger.error(
        response.error,
        "failed to configure activity category standard"
      );
      return { error: response.statusText };
    }

    revalidatePath("/getting-started");
    return { error: null, success: true };
  } catch (error) {
    return { error: "Error setting category standard" };
  }
}
