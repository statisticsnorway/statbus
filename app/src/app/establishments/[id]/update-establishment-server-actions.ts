"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { createServerLogger } from "@/lib/server-logger";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { getEditMetadata } from "@/app/legal-units/[id]/update-legal-unit-server-actions";

export async function updateEstablishment(
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

  const { valid_from, valid_until, ...updatedFields } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;

    const { data: exactSlice, error: exactErr } = await client
      .from("establishment__for_portion_of_valid")
      .select("id")
      .eq("id", parseInt(id, 10))
      .eq("valid_from", valid_from as string)
      .eq("valid_until", valid_until as string)
      .limit(1);
    if (exactErr) {
      return {
        status: "error" as const,
        message: exactErr.message,
      };
    }
    if (exactSlice && exactSlice.length === 1) {
      const response = await client
        .from("establishment")
        .update({ ...updatedFields, ...metadata })
        .eq("id", parseInt(id, 10))
        .eq("valid_from", valid_from as string)
        .eq("valid_to", valid_until as string);

      if (response.status >= 400) {
        return { status: "error", message: response.statusText };
      }
    } else {
      const response = await client
        .from("establishment__for_portion_of_valid")
        .update({ ...validatedFields.data, ...metadata })
        .eq("id", parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
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
