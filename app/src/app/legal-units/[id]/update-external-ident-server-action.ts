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
  const { data } = await client.rpc("auth_status", {}, { get: true });
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

  const [[identTypeCode, newIdentValue]] = Object.entries(validatedFields.data);

  const identType = externalIdentTypes.find(
    (type) => type.code === identTypeCode
  );
  if (!identType) {
    return {
      status: "error",
      message: `Invalid external identifier type: ${identTypeCode}`,
    };
  }
  const identTypeId = identType.id;
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
          message: `Cannot delete ${identTypeCode}. Unit must have at least one external identifier.`,
        };
      }
      response = await client
        .from("external_ident")
        .delete()
        .eq("type_id", identTypeId!)
        .eq(unitIdField, parseInt(id));
    } else if (!exisitingIdent || exisitingIdent.length === 0) {
      response = await client.from("external_ident").insert({
        ident: newIdentValue,
        [unitIdField]: parseInt(id),
        type_id: identTypeId!,
        edit_by_user_id: userId,
      });
    } else {
      response = await client
        .from("external_ident")
        .update({
          ident: newIdentValue,
          edit_by_user_id: userId,
          edit_at: new Date().toISOString(),
        })
        .eq("type_id", identTypeId!)
        .eq(unitIdField, parseInt(id));
    }
    if (response?.error) {
      logger.error(response.error, `failed to update ${identTypeCode}`);
      return {
        status: "error",
        message: `failed to update ${identTypeCode}: ${response.error.message}`,
      };
    }

    revalidatePath(`/${unitType}s/${id}`);
    return {
      status: "success",
      message: `${identTypeCode} successfully updated`,
    };
  } catch (error) {
    return {
      status: "error",
      message: `failed to update ${identTypeCode}`,
    };
  }
}
