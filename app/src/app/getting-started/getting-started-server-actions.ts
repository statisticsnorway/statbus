"use server";
import { redirect, RedirectType } from "next/navigation";
import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";
import { createClient } from "@/lib/supabase/server";
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
    const authFetch = setupAuthorizedFetchFn();
    const response = await authFetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/${uploadView}`,
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

    revalidatePath("/getting-started", "page");

    return { error: null, success: true };
  } catch (e) {
    return { error: `failed to upload in view ${uploadView}` };
  }
}

export async function setCategoryStandard(formData: FormData) {
  "use server";
  const client = createClient();
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
  } catch (error) {
    return { error: "Error setting category standard" };
  }

  redirect("/getting-started/upload-regions", RedirectType.push);
}
