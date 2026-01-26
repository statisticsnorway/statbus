"use server";
import { createServerLogger } from "@/lib/server-logger";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { zfd } from "zod-form-data";
import { baseDataStore } from "@/context/BaseDataStore";
import { _parseAuthStatusRpcResponseToAuthStatus } from "@/lib/auth.types";

const externalIdentsSchema = zfd.formData(
  z.record(
    z.string(),
    z
      .string()
      .regex(/^[^\s]*$/, {
        message: "Value must not contain spaces",
      })
      .optional()
  )
);

/**
 * Constructs a hierarchical identifier path from form data.
 * Form fields are named like: census_ident_census, census_ident_region, census_ident_surveyor, census_ident_unit_no
 * The labels (like "census.region.surveyor.unit_no") tell us the level names.
 */
function constructHierarchicalPath(
  identTypeCode: string,
  labels: string,
  formData: Record<string, string | undefined>
): string | null {
  const levelNames = labels.split(".");
  const parts: string[] = [];

  for (const levelName of levelNames) {
    const fieldKey = `${identTypeCode}_${levelName}`;
    const value = formData[fieldKey];
    if (value) {
      parts.push(value);
    } else {
      // If any level is empty, stop constructing the path
      break;
    }
  }

  // Return null if no parts, otherwise join with dots
  return parts.length > 0 ? parts.join(".") : null;
}

export async function updateExternalIdent(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const logger = await createServerLogger();
  const client = await getServerRestClient();
  const validatedFields = externalIdentsSchema.safeParse(formData);
  const { externalIdentTypes } = await baseDataStore.getBaseData(client);

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
  const { data } = await client.rpc("auth_status", undefined, { get: true });
  const parsedAuthStatus = _parseAuthStatusRpcResponseToAuthStatus(data);

  if (!parsedAuthStatus.isAuthenticated || !parsedAuthStatus.user) {
    logger.warn("User is not authenticated or user details are missing.");
    return {
      status: "error",
      message: "User not authenticated.",
    };
  }
  const userId = parsedAuthStatus.user.uid;

  const unitIdField = `${unitType}_id`;

  // Get first key to determine which identifier type we're editing
  const firstKey = Object.keys(validatedFields.data)[0];
  
  // Detect if this is a hierarchical identifier by checking for underscore pattern
  // e.g., "census_ident_census" -> "census_ident"
  const identTypeCode = firstKey.includes("_") && 
    externalIdentTypes.some(t => t.shape === "hierarchical" && firstKey.startsWith(t.code + "_"))
    ? firstKey.substring(0, firstKey.lastIndexOf("_"))
    : firstKey;
  
  // For hierarchical types, find the actual type code by checking prefixes
  const identType = externalIdentTypes.find(
    (type) => {
      if (type.shape === "hierarchical" && type.labels) {
        // Check if any form key starts with this type's code followed by underscore
        return Object.keys(validatedFields.data).some(key => 
          key.startsWith(type.code + "_")
        );
      }
      return type.code === firstKey;
    }
  );
  
  if (!identType) {
    return {
      status: "error",
      message: `Invalid external identifier type: ${firstKey}`,
    };
  }
  const identTypeId = identType.id;
  const isHierarchical = identType.shape === "hierarchical";
  
  // Construct the value based on identifier type
  let newIdentValue: string | null = null;
  if (isHierarchical && identType.labels) {
    newIdentValue = constructHierarchicalPath(
      identType.code!,
      identType.labels,
      validatedFields.data
    );
  } else {
    newIdentValue = validatedFields.data[firstKey] || null;
  }
  
  try {
    const { data: exisitingIdent, error } = await client
      .from("external_ident")
      .select("id")
      .eq("type_id", identTypeId!)
      .eq(unitIdField, parseInt(id));
    if (error) {
      console.error("Error fetching existing record:", error);
    }

    let response;
    if (!newIdentValue) {
      const { count } = await client
        .from("external_ident")
        .select("*", { count: "exact", head: true })
        .eq(unitIdField, parseInt(id));
      if (count === 1) {
        return {
          status: "error",
          message: `Cannot delete ${identType.code}. Unit must have at least one external identifier.`,
        };
      }
      response = await client
        .from("external_ident")
        .delete()
        .eq("type_id", identTypeId!)
        .eq(unitIdField, parseInt(id));
    } else if (!exisitingIdent || exisitingIdent.length === 0) {
      // Note: 'shape' and 'labels' are derived by trigger from type_id
      // but TypeScript requires them. The trigger will override our value.
      const insertData: Record<string, unknown> = {
        [unitIdField]: parseInt(id),
        type_id: identTypeId!,
        edit_by_user_id: userId,
        shape: identType.shape!, // Will be overwritten by trigger
      };
      
      if (isHierarchical) {
        insertData.idents = newIdentValue;
      } else {
        insertData.ident = newIdentValue;
      }
      
      response = await client.from("external_ident").insert(insertData);
    } else {
      const updateData: Record<string, unknown> = {
        edit_by_user_id: userId,
        edit_at: new Date().toISOString(),
      };
      
      if (isHierarchical) {
        updateData.idents = newIdentValue;
        updateData.ident = null; // Clear the regular ident field
      } else {
        updateData.ident = newIdentValue;
        updateData.idents = null; // Clear the hierarchical idents field
      }
      
      response = await client
        .from("external_ident")
        .update(updateData)
        .eq("type_id", identTypeId!)
        .eq(unitIdField, parseInt(id));
    }
    if (response?.error) {
      logger.error(response.error, `failed to update ${identType.code}`);
      return {
        status: "error",
        message: `failed to update ${identType.code}: ${response.error.message}`,
      };
    }

    revalidatePath(`/${unitType}s/${id}`);
    return {
      status: "success",
      message: `${identType.code} successfully updated`,
    };
  } catch (error) {
    return {
      status: "error",
      message: `failed to update ${identType.code}`,
    };
  }
}
