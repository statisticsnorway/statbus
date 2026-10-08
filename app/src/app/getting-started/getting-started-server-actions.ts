"use server";
import { fetchWithAuth, getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";

import { createServerLogger } from "@/lib/server-logger";
import {
  explainUploadFailure,
  prepareUpload,
  viewColumnsFromOpenApi,
} from "./upload-csv-check";

interface State {
  readonly error: string | null;
  readonly success?: boolean;
}

export type UploadView =
  | "region_upload"
  | "import_legal_unit_current"
  | "activity_category_enabled_custom"
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

  // STATBUS-470: say plainly what is wrong with the file. Check it before
  // sending anything, and translate PostgREST's rejection (schema cache,
  // varchar, not-null) into the columns, row and limit involved.
  const prepared = await prepareUpload(formData.get(filename));
  if (!prepared.ok) return { error: prepared.error };

  try {
    const logger = await createServerLogger();
    const client = await getServerRestClient();

    // Get the base URL from the client
    const postgrestUrl = client.url;

    // Use fetchWithAuth which correctly prepares headers including Authorization and X-Forwarded-*.
    // We override Content-Type for CSV upload.
    const response = await fetchWithAuth(`${postgrestUrl}/${uploadView}`, {
      method: "POST",
      headers: {
        "Content-Type": "text/csv",
      },
      // The checked text: a UTF-8 byte-order mark is already removed, so it
      // cannot become part of the first column's name.
      body: prepared.text,
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      logger.error(
        { status: response.status, body: body.slice(0, 2000) },
        `upload to ${uploadView} failed with status ${response.status} ${response.statusText}`
      );
      // The view's columns, to name what IS accepted and which columns a
      // length limit applies to. Best effort: without them the message
      // still names what the file got wrong.
      const columns = await (async () => {
        try {
          const openapi = await fetchWithAuth(`${postgrestUrl}/`, {
            headers: { Accept: "application/openapi+json" },
          });
          return openapi?.ok
            ? viewColumnsFromOpenApi(await openapi.json(), uploadView)
            : null;
        } catch {
          return null;
        }
      })();
      return {
        error: explainUploadFailure(
          { status: response.status, statusText: response.statusText, body },
          prepared.records,
          columns
        ),
      };
    }

    return { error: null, success: true };
  } catch (e) {
    return {
      error: `The upload could not be sent: ${e instanceof Error ? e.message : String(e)}`,
    };
  }
}

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
