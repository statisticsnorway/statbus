"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { createServerLogger } from "@/lib/server-logger";
import { locationSchema } from "@/app/legal-units/[id]/general-info/validation";
import { activitySchema } from "./classifications/validation";
import { statsSchema } from "./statistical-variables/validation";
import { _parseAuthStatusRpcResponseToAuthStatus } from "@/lib/auth.types";
import type { TablesInsert } from "@/lib/database.types";
import { contactInfoSchema } from "./contact/validation";
import {
  resolveSchemaByType,
} from "@/components/form/helper-functions";
import { describeInvalidForm, type EditSchema } from "@/components/form/metadata-validation";
import { capToExistence, unitExistence, type UnitRow } from "@/components/form/unit-existence";

export async function getEditMetadata(client: Awaited<ReturnType<typeof getServerRestClient>>) {
  const { data } = await client.rpc("auth_status", {}, { get: true });
  const parsedAuthStatus = _parseAuthStatusRpcResponseToAuthStatus(data);
  if (!parsedAuthStatus.isAuthenticated || !parsedAuthStatus.user) {
    return {
      error: {
        status: "error" as const,
        message: "User not authenticated.",
      },
      metadata: null,
    };
  }
  return {
    error: null,
    metadata: {
      edit_by_user_id: parsedAuthStatus.user.uid,
      edit_at: new Date().toISOString(),
    },
  };
}
export async function updateLegalUnit(
  id: string,
  schemaType: SchemaType,
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const schema = resolveSchemaByType(schemaType);
  const validatedFields = schema.safeParse(formData);
  if (!validatedFields.success) {
    return describeInvalidForm(validatedFields.error);
  }

  const { valid_from, valid_to } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    // Handle image upload/delete
    let imageId: number | null | undefined = undefined;
    const deleteImage = formData.get("delete_image") === "true";
    const imageFile = formData.get("image") as File | null;

    if (deleteImage) {
      imageId = null;
    } else if (imageFile && imageFile.size > 0) {
      const logger = await createServerLogger();
      const bytes = await imageFile.arrayBuffer();
      const buffer = Buffer.from(bytes);
      const hexData = "\\x" + buffer.toString("hex");

      const { data: imageData, error: imageError } = await client
        .from("image")
        .insert({
          data: hexData,
          type: imageFile.type,
        })
        .select("id")
        .single();

      if (imageError || !imageData) {
        logger.error(imageError, "failed to insert image");
        return {
          status: "error",
          message: imageError?.message || "Failed to upload image",
        };
      }

      imageId = imageData.id;
    }

    // Extract image-related fields that shouldn't be sent to database
    const { image, delete_image, ...dataFields } = validatedFields.data;

    const payload = {
      ...dataFields,
      ...metadata,
      ...(imageId !== undefined && { image_id: imageId }),
    };
    const { data: overlappingRows, error: overlapError } = await client
      .from("legal_unit")
      .select("*")
      .eq("id", parseInt(id, 10))
      .lte("valid_from", valid_to)
      .gte("valid_to", valid_from);

    if (overlapError) {
      return { status: "error", message: overlapError.message };
    }

    if (overlappingRows && overlappingRows.length > 0) {
      // The for-portion-of view applies the edit where the unit exists inside
      // [valid_from, valid_to]; a portion reaching beyond the unit is clipped.
      const response = await client
        .from("legal_unit__for_portion_of_valid")
        .update(payload)
        .eq("id", parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    } else {
      return {
        status: "error",
        message: `The legal unit does not exist between ${valid_from} and ${valid_to}; choose a period in which it exists.`,
      };
    }
    revalidatePath("/legal-units/[id]", "page");
  } catch (error) {
    return { status: "error", message: "failed to update legal unit" };
  }

  return { status: "success", message: "Legal unit successfully updated" };
}

export async function updateLegalUnitImage(
  id: string,
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  try {
    const file = formData.get("image") as File;
    if (!file) {
      return {
        status: "error",
        message: "No image file provided",
      };
    }

    // Convert file to hex-encoded bytea for PostgreSQL
    const bytes = await file.arrayBuffer();
    const buffer = Buffer.from(bytes);
    const hexData = "\\x" + buffer.toString("hex");

    // Insert image into public.image table
    const { data: imageData, error: imageError } = await client
      .from("image")
      .insert({
        data: hexData,
        type: file.type,
      })
      .select("id")
      .single();

    if (imageError || !imageData) {
      logger.error(imageError, "failed to insert image");
      return {
        status: "error",
        message: imageError?.message || "Failed to upload image",
      };
    }

    // Update legal_unit with new image_id
    const { error: updateError } = await client
      .from("legal_unit")
      .update({ image_id: imageData.id })
      .eq("id", parseInt(id, 10));

    if (updateError) {
      logger.error(updateError, "failed to update legal_unit image_id");
      return {
        status: "error",
        message: updateError.message,
      };
    }

    revalidatePath("/legal-units/[id]", "page");
    return {
      status: "success",
      message: "Image uploaded successfully",
    };
  } catch (error) {
    logger.error(error, "failed to upload legal unit image");
    return {
      status: "error",
      message: "Failed to upload image",
    };
  }
}

export async function deleteLegalUnitImage(
  id: string,
  _prevState: unknown
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  try {
    // Get current image_id before clearing it (from any temporal version)
    const { data: legalUnits, error: fetchError } = await client
      .from("legal_unit")
      .select("image_id")
      .eq("id", parseInt(id, 10))
      .limit(1);

    if (fetchError || !legalUnits || legalUnits.length === 0 || !legalUnits[0].image_id) {
      return {
        status: "error",
        message: "No image to delete",
      };
    }

    const imageId = legalUnits[0].image_id;

    // Clear image_id from ALL temporal versions of this legal_unit
    const { error: updateError } = await client
      .from("legal_unit")
      .update({ image_id: null })
      .eq("id", parseInt(id, 10));

    if (updateError) {
      logger.error(updateError, "failed to clear legal_unit image_id");
      return {
        status: "error",
        message: updateError.message,
      };
    }

    // Delete the image record (optional - could keep for audit trail)
    const { error: deleteError } = await client
      .from("image")
      .delete()
      .eq("id", imageId);

    if (deleteError) {
      logger.error(deleteError, "failed to delete image record");
      // Don't fail - image_id is already cleared
    }

    revalidatePath("/legal-units/[id]", "page");
    return {
      status: "success",
      message: "Image deleted successfully",
    };
  } catch (error) {
    logger.error(error, "failed to delete legal unit image");
    return {
      status: "error",
      message: "Failed to delete image",
    };
  }
}

export async function updateLocation(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  return upsertTemporalRecord({
    id: id,
    unitType: unitType,
    tableName: "location",
    schemaType: locationSchema,
    formData,
    naturalKeys: ["type"],
    revalidationPath: ``,
  });
}

export async function updateContact(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  return upsertTemporalRecord({
    id: id,
    unitType: unitType,
    tableName: "contact",
    schemaType: contactInfoSchema,
    formData,
    revalidationPath: `contact`,
  });
}

export async function updateActivity(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  return upsertTemporalRecord({
    id: id,
    unitType: unitType,
    tableName: "activity",
    schemaType: activitySchema,
    formData,
    naturalKeys: ["type"],
    revalidationPath: `classifications`,
  });
}

export async function updateStatisticalVariables(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  return upsertTemporalRecord({
    id: id,
    unitType: unitType,
    tableName: "stat_for_unit",
    schemaType: statsSchema,
    formData,
    naturalKeys: ["stat_definition_id"],
    revalidationPath: "statistical-variables",
  });
}

interface upsertTemporalRecordParams {
  id: string;
  unitType: "establishment" | "legal_unit";
  tableName: "activity" | "location" | "stat_for_unit" | "contact";
  schemaType: EditSchema;
  formData: FormData;
  naturalKeys?: string[];
  revalidationPath: string;
}

export async function upsertTemporalRecord({
  id,
  unitType,
  tableName,
  schemaType,
  formData,
  revalidationPath,
  naturalKeys = [],
}: upsertTemporalRecordParams): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = schemaType.safeParse(formData);

  if (!validatedFields.success) {
    return describeInvalidForm(validatedFields.error);
  }
  const unitIdFieldName = `${unitType}_id`;
  const unitId = parseInt(id, 10);
  const { valid_from, valid_to } = validatedFields.data;
  const naturalKeyValues: Record<string, string | number> = {
    [unitIdFieldName]: unitId,
  };
  for (const key of naturalKeys) {
    const value = validatedFields.data[key];
    if (typeof value === "string" || typeof value === "number") {
      naturalKeyValues[key] = value;
    }
  }
  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;
    const payload = { ...validatedFields.data, ...metadata };
    let overlapQuery = client
      .from(tableName)
      .select("*")
      .lte("valid_from", valid_to)
      .gte("valid_to", valid_from);
    for (const key in naturalKeyValues) {
      overlapQuery = overlapQuery.eq(key, naturalKeyValues[key]);
    }
    const { data: overlappingRows, error: overlapError } = await overlapQuery;
    if (overlapError) {
      return {
        status: "error" as const,
        message: overlapError.message,
      };
    }
    if (overlappingRows && overlappingRows.length > 0) {
      // The for-portion-of view applies the edit where the record exists
      // inside [valid_from, valid_to]; a portion reaching beyond it is clipped.
      let updateQuery = client
        .from(`${tableName}__for_portion_of_valid`)
        .update(payload);

      for (const key in naturalKeyValues) {
        updateQuery = updateQuery.eq(key, naturalKeyValues[key]);
      }
      const response = await updateQuery;
      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    } else {
      // A new record is valid only where its unit exists. The unit's history is
      // many rows, so its existence is their union (unitExistence); the record is
      // stored on the part of [valid_from, valid_to] inside it (capToExistence).
      // The temporal foreign key (e.g. contact_legal_unit_id_valid) enforces the
      // same rule in the database.
      const parentTable = unitType;
      const { data: parentRows, error: parentError } = await client
        .from(parentTable)
        .select("valid_from, valid_until")
        .eq("id", unitId)
        .order("valid_from");

      if (parentError) {
        return { status: "error", message: parentError.message };
      }

      const existence = unitExistence((parentRows ?? []) as UnitRow[]);
      const capped = capToExistence(existence, valid_from, valid_to);
      if (!capped) {
        const spans = existence
          .map((s) => `${s.validFrom} – ${s.validTo === "infinity" ? "Present" : s.validTo}`)
          .join(", ");
        return {
          status: "error",
          message: `The ${unitType.replace("_", " ")} does not exist between ${valid_from} and ${valid_to === "infinity" ? "Present" : valid_to}. It exists ${spans}.`,
        };
      }

      // The schema read the form into this table's columns; the database checks the row.
      const insertPayload = {
        ...payload,
        ...naturalKeyValues,
        valid_from: capped.validFrom,
        valid_to: capped.validTo,
      } as TablesInsert<typeof tableName> & { id?: number };
      let templateQuery = client.from(tableName).select("id").limit(1);
      for (const key in naturalKeyValues) {
        templateQuery = templateQuery.eq(key, naturalKeyValues[key]);
      }
      const { data, error: templateError } = await templateQuery;

      if (templateError) {
        return {
          status: "error",
          message: `Failed to fetch template record: ${templateError.message}`,
        };
      }

      if (data && data.length > 0) {
        insertPayload.id = data[0].id;
      }

      const response = await client.from(tableName).insert([insertPayload]);

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    }

    revalidatePath(
      `/${unitType.replace("_", "-")}s/[id]/${revalidationPath}`,
      "page"
    );
  } catch (error) {
    return { status: "error", message: `failed to update ${tableName}` };
  }

  return { status: "success", message: `${tableName} successfully updated` };
}

/** The records a unit has over time that the edit form can remove (STATBUS-611). */
const REMOVABLE_TABLES = ["contact", "location", "activity", "stat_for_unit"] as const;
type RemovableTable = (typeof REMOVABLE_TABLES)[number];
/** The row keys that pick one unit's record in a removable table (EditFieldSource.match). */
const REMOVABLE_MATCH_KEYS = ["legal_unit_id", "establishment_id", "type", "stat_definition_id", "category_id"];

export interface RemoveTemporalRecordArgs {
  table: RemovableTable;
  /** The record's row keys, as the form's EditFieldSource names them. */
  match: Record<string, string | number>;
  /** The range removed, ISO dates inclusive; validTo null is open-ended. */
  validFrom: string;
  validTo: string | null;
}

/**
 * Removes a unit's record (a contact, location, activity or statistic) over
 * [validFrom, validTo]: the edit form's Remove. Rows the range cuts through are
 * split, so the record stays before and after it. This is the one call Remove
 * makes, so its backend can change without the form changing:
 * PROTOTYPE: calls public.remove_for_portion_of (tmp/611-remove-prototype.sql,
 * local dev database only). It becomes the for_portion_of view's delete
 * protocol, PATCH {id: null, valid_from, valid_until} (sql_saga, STATBUS-611).
 */
export async function removeTemporalRecord({
  table,
  match,
  validFrom,
  validTo,
}: RemoveTemporalRecordArgs): Promise<UpdateResponse> {
  if (!REMOVABLE_TABLES.includes(table)) {
    return { status: "error", message: `Records of ${table} cannot be removed here` };
  }
  const keys = Object.keys(match);
  if (keys.length === 0 || keys.some((k) => !REMOVABLE_MATCH_KEYS.includes(k))) {
    return { status: "error", message: "The record to remove is not named by its unit" };
  }
  const logger = await createServerLogger();
  const client = await getServerRestClient();
  try {
    // The table is one of REMOVABLE_TABLES, named at run time as in upsertTemporalRecord.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let idQuery = (client as any).from(table).select("id");
    for (const [k, v] of Object.entries(match)) idQuery = idQuery.eq(k, v);
    const { data: rows, error: idError } = await idQuery;
    if (idError) return { status: "error", message: idError.message };
    const ids = [...new Set((rows ?? []).map((r: { id: number }) => r.id))];
    if (ids.length === 0) return { status: "error", message: "There is nothing to remove" };
    for (const recordId of ids) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (client as any).rpc("remove_for_portion_of", {
        table_name: table,
        record_id: recordId,
        valid_from: validFrom,
        valid_to: validTo ?? "infinity",
      });
      if (error) return { status: "error", message: error.message };
    }
  } catch (error) {
    logger.error(error, `failed to remove ${table}`);
    return { status: "error", message: `Failed to remove the ${table.replace(/_/g, " ")}` };
  }
  const unitType = "legal_unit_id" in match ? "legal-units" : "establishments";
  revalidatePath(`/${unitType}/[id]`, "layout");
  return {
    status: "success",
    message: `${validFrom} – ${validTo ?? "Present"}`,
  };
}

export async function setPrimaryLegalUnit(id: number) {
  "use server";
  const logger = await createServerLogger();
  const client = await getServerRestClient();
  const { error } = await client.rpc("set_primary_legal_unit_for_enterprise", {
    legal_unit_id: id,
  });

  if (error) {
    logger.error(error, "failed to set primary legal unit");
    return;
  }

  revalidatePath("/legal-units/[id]", "page");
}
