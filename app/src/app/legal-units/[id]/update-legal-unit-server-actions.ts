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
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const validatedFields = generalInfoSchema.safeParse(formData);

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

  const { valid_from, valid_to, ...updatedFields } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const payload = { ...validatedFields.data, ...metadata };

    const response = await client
      .from("legal_unit__for_portion_of_valid")
      .update(payload)
      .eq("id", parseInt(id, 10))
      .gte("valid_from", valid_from)
      .lte("valid_to", valid_to);

    if (response.status >= 400) {
      return {
        status: "error",
        message: response.error?.message || response.statusText,
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
  locationType: "physical" | "postal",
  unitType: "establishment" | "legal_unit",
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  "use server";
  const client = await getServerRestClient();
  const validatedFields = locationSchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse location form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const unitIdField = `${unitType}_id`;
  const { valid_from, valid_to, ...updatedFields } = validatedFields.data;
  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const { data: exactSlice, error: exactErr } = await client
      .from("location__for_portion_of_valid")
      .select(unitIdField)
      .eq(unitIdField, parseInt(id, 10))
      .eq("type", locationType)
      .eq("valid_from", valid_from as string)
      .eq("valid_to", valid_to as string)
      .limit(1);
    if (exactErr) {
      return {
        status: "error" as const,
        message: exactErr.message,
      };
    }
    if (exactSlice && exactSlice.length === 1) {
      const response = await client
        .from("location")
        .update({ ...updatedFields, ...metadata })
        .eq(unitIdField, parseInt(id, 10))
        .eq("type", locationType)
        .eq("valid_from", valid_from as string)
        .eq("valid_to", valid_to as string);

      if (response.status >= 400) {
        return { status: "error", message: response.statusText };
      }
    } else {
      const response = await client
        .from("location__for_portion_of_valid")
        .update({ ...validatedFields.data, ...metadata })
        .eq("type", locationType)
        .eq(unitIdField, parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    }

    revalidatePath(`/${unitType.replace("_", "-")}/[id]", "page`);
  } catch (error) {
    return { status: "error", message: "failed to update location" };
  }

  return { status: "success", message: "Location successfully updated" };
}

export async function updateContact(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  "use server";
  const client = await getServerRestClient();
  const validatedFields = contactInfoSchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse location form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const unitIdField = `${unitType}_id`;
  const { valid_from, valid_to, ...updatedFields } = validatedFields.data;
  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const { data: exactSlice, error: exactErr } = await client
      .from("contact__for_portion_of_valid")
      .select(unitIdField)
      .eq(unitIdField, parseInt(id, 10))
      .eq("valid_from", valid_from as string)
      .eq("valid_to", valid_to as string)
      .limit(1);
    if (exactErr) {
      return {
        status: "error" as const,
        message: exactErr.message,
      };
    }
    if (exactSlice && exactSlice.length === 1) {
      const response = await client
        .from("contact")
        .update({ ...updatedFields, ...metadata })
        .eq(unitIdField, parseInt(id, 10))
        .eq("valid_from", valid_from as string)
        .eq("valid_to", valid_to as string);

      if (response.status >= 400) {
        return { status: "error", message: response.statusText };
      }
    } else {
      const response = await client
        .from("contact__for_portion_of_valid")
        .update({ ...validatedFields.data, ...metadata })
        .eq(unitIdField, parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    }

    revalidatePath(`/${unitType.replace("_", "-")}/[id]/contact", "page`);
  } catch (error) {
    return { status: "error", message: "failed to update contact" };
  }

  return { status: "success", message: "Contact successfully updated" };
}

export async function updateActivity(
  id: string,
  activityType: "primary" | "secondary" | "ancilliary",
  unitType: "establishment" | "legal_unit",
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  "use server";
  const client = await getServerRestClient();
  const validatedFields = activitySchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse activity form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const unitIdField = `${unitType}_id`;
  const { valid_from, valid_to, ...updatedFields } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;
    const { data: exactSlice, error: exactErr } = await client
      .from("activity__for_portion_of_valid")
      .select(unitIdField)
      .eq(unitIdField, parseInt(id, 10))
      .eq("type", activityType)
      .eq("valid_from", valid_from as string)
      .eq("valid_to", valid_to as string)
      .limit(1);
    if (exactErr) {
      return {
        status: "error" as const,
        message: exactErr.message,
      };
    }
    if (exactSlice && exactSlice.length === 1) {
      const response = await client
        .from("activity")
        .update({ ...updatedFields, ...metadata })
        .eq(unitIdField, parseInt(id, 10))
        .eq("type", activityType)
        .eq("valid_from", valid_from as string)
        .eq("valid_to", valid_to as string);

      if (response.status >= 400) {
        return { status: "error", message: response.statusText };
      }
    } else {
      const response = await client
        .from("activity__for_portion_of_valid")
        .update({ ...validatedFields.data, ...metadata })
        .eq("type", activityType)
        .eq(unitIdField, parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    }

    revalidatePath(
      `/${unitType.replace("_", "-")}/[id]/classifications", "page`
    );
  } catch (error) {
    return { status: "error", message: "failed to update activity" };
  }

  return { status: "success", message: "Activity successfully updated" };
}

export async function updateStatisticalVariables(
  id: string,
  unitType: "establishment" | "legal_unit",
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  "use server";
  const client = await getServerRestClient();
  const validatedFields = statsSchema.safeParse(formData);

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse location form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const unitIdField = `${unitType}_id`;
  const { valid_from, valid_to, stat_definition_id, ...updatedFields } =
    validatedFields.data;
  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const { data: exactSlice, error: exactErr } = await client
      .from("stat_for_unit__for_portion_of_valid")
      .select(unitIdField)
      .eq(unitIdField, parseInt(id, 10))
      .eq("stat_definition_id", stat_definition_id as number)
      .eq("valid_from", valid_from as string)
      .eq("valid_to", valid_to as string)
      .limit(1);
    if (exactErr) {
      return {
        status: "error" as const,
        message: exactErr.message,
      };
    }
    if (exactSlice && exactSlice.length === 1) {
      const response = await client
        .from("stat_for_unit")
        .update({ ...updatedFields, ...metadata })
        .eq(unitIdField, parseInt(id, 10))
        .eq("stat_definition_id", stat_definition_id as number)
        .eq("valid_from", valid_from as string)
        .eq("valid_to", valid_to as string);

      if (response.status >= 400) {
        return { status: "error", message: response.statusText };
      }
    } else {
      const response = await client
        .from("stat_for_unit__for_portion_of_valid")
        .update({ ...validatedFields.data, ...metadata })
        .eq(unitIdField, parseInt(id, 10))
        .eq("stat_definition_id", stat_definition_id as number);

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    }

    revalidatePath(
      `/${unitType.replace("_", "-")}/[id]/statistical-variables", "page`
    );
  } catch (error) {
    return {
      status: "error",
      message: "failed to update statistical variable",
    };
  }

  return {
    status: "success",
    message: "Statistical variable successfully updated",
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

