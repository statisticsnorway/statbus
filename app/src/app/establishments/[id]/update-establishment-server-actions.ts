"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { createServerLogger } from "@/lib/server-logger";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { getEditMetadata } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import {
  resolveSchemaByType,
  checkValidityBounds,
} from "@/components/form/helper-functions";

export async function updateEstablishment(
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
      .from("establishment")
      .select("*")
      .eq("id", parseInt(id, 10))
      .lte("valid_from", valid_to)
      .gte("valid_to", valid_from);

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
        "establishment"
      );
      if (boundsError) return boundsError;
      const response = await client
        .from("establishment__for_portion_of_valid")
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
          "Cannot insert establishment. Only updates within the existing date range are allowed.",
      };
    }

    revalidatePath("/establishments/[id]", "page");
  } catch (error) {
    return { status: "error", message: "failed to update establishment" };
  }

  return { status: "success", message: "Establishment successfully updated" };
}

export async function setPrimaryEstablishment(id: number) {
  "use server";
  const logger = await createServerLogger();
  const client = await getServerRestClient();
  const { error } = await client.rpc(
    "set_primary_establishment_for_legal_unit",
    { establishment_id: id }
  );

  if (error) {
    logger.error(error, "failed to set primary establishment");
    return;
  }

  revalidatePath("/establishments/[id]", "page");
}
