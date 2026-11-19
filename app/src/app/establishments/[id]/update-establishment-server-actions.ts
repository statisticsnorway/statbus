"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { createServerLogger } from "@/lib/server-logger";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { getEditMetadata } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import {
  resolveSchemaByType,
} from "@/components/form/helper-functions";
import { describeInvalidForm } from "@/components/form/metadata-validation";
import { discardUnsavedPhoto, storeUnitPhoto } from "@/components/form/unit-photo-server";

export async function updateEstablishment(
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

    const { data: overlappingRows, error: overlapError } = await client
      .from("establishment")
      .select("id")
      .eq("id", parseInt(id, 10))
      .lte("valid_from", valid_to)
      .gte("valid_to", valid_from);

    if (overlapError) {
      return {
        status: "error" as const,
        message: overlapError.message,
      };
    }
    if (!overlappingRows || overlappingRows.length === 0) {
      return {
        status: "error",
        message: `The establishment does not exist between ${valid_from} and ${valid_to}; choose a period in which it exists.`,
      };
    }

    const stored = await storeUnitPhoto(client, formData);
    if ("error" in stored) return { status: "error", message: stored.error };

    // The photo travels as image_id; the form's file fields are not columns.
    const { image, delete_image, ...dataFields } = validatedFields.data;
    const payload = {
      ...dataFields,
      ...metadata,
      ...(stored.photo !== undefined && { image_id: stored.photo }),
    };

    // The for-portion-of view applies the edit where the unit exists inside
    // [valid_from, valid_to]; a portion reaching beyond the unit is clipped.
    const response = await client
      .from("establishment__for_portion_of_valid")
      .update(payload)
      .eq("id", parseInt(id, 10));

    if (response.status >= 400) {
      await discardUnsavedPhoto(client, stored.photo);
      return {
        status: "error",
        message: response.error?.message || response.statusText,
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
