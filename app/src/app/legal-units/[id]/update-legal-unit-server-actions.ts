"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { createServerLogger } from "@/lib/server-logger";
import { locationSchema } from "@/app/legal-units/[id]/general-info/validation";
import { activitySchema } from "./classifications/validation";
import { statsSchema } from "./statistical-variables/validation";
import { _parseAuthStatusRpcResponseToAuthStatus } from "@/lib/auth.types";
import { contactInfoSchema } from "./contact/validation";
import {
  resolveSchemaByType,
  checkValidityBounds,
} from "@/components/form/helper-functions";
import { z } from "zod";

export async function getEditMetadata(client: any) {
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
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const schema = resolveSchemaByType(schemaType);
  const validatedFields = schema.safeParse(formData);
  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { valid_from, valid_to } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const payload = { ...validatedFields.data, ...metadata };
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
      const boundsError = checkValidityBounds(
        overlappingRows,
        valid_from,
        valid_to,
        "legal unit"
      );
      if (boundsError) return boundsError;
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
        message:
          "Cannot insert legal unit. Only updates within the existing date range are allowed.",
      };
    }
    revalidatePath("/legal-units/[id]", "page");
  } catch (error) {
    return { status: "error", message: "failed to update legal unit" };
  }

  return { status: "success", message: "Legal unit successfully updated" };
}

export async function updateLocation(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: any,
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
  _prevState: any,
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
  _prevState: any,
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
  _prevState: any,
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
  schemaType: z.Schema;
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
    return {
      status: "error",
      message: `failed to parse form data for ${tableName}`,
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const unitIdFieldName = `${unitType}_id`;
  const unitId = parseInt(id, 10);
  const { valid_from, valid_to } = validatedFields.data;
  const naturalKeyValues: { [key: string]: any } = {
    [unitIdFieldName]: unitId,
  };
  for (const key of naturalKeys) {
    if (key in validatedFields.data) {
      naturalKeyValues[key] = validatedFields.data[key];
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
      const boundsError = checkValidityBounds(
        overlappingRows,
        valid_from,
        valid_to,
        tableName
      );
      if (boundsError) return boundsError;

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
      let insertPayload = { ...payload, ...naturalKeyValues };
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

