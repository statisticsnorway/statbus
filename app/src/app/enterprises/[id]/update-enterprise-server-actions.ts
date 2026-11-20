"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { zfd } from "zod-form-data";
import { getEditMetadata } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { describeInvalidForm } from "@/components/form/metadata-validation";

/**
 * The enterprise's short name (public.enterprise.short_name, at most 16 characters):
 * the name the enterprise goes by everywhere when set, for example "SSB" for
 * Statistics Norway's enterprise. Empty clears it, and the enterprise is named after
 * its primary legal unit again. An enterprise has no periods, so this is one value
 * for all time.
 */
const shortNameSchema = zfd.formData({
  short_name: zfd.text(
    z
      .string()
      .trim()
      .max(16, "A short name has at most 16 characters")
      .optional()
  ),
});

export async function updateEnterpriseShortName(
  id: string,
  _prevState: unknown,
  formData: FormData
): Promise<UpdateResponse> {
  const validated = shortNameSchema.safeParse(formData);
  if (!validated.success) return describeInvalidForm(validated.error);

  const client = await getServerRestClient();
  const { error: metadataError, metadata } = await getEditMetadata(client);
  if (metadataError) return metadataError;

  const { error } = await client
    .from("enterprise")
    .update({ short_name: validated.data.short_name ?? null, ...metadata })
    .eq("id", parseInt(id, 10));
  if (error) return { status: "error", message: error.message };

  revalidatePath("/enterprises/[id]", "page");
  return {
    status: "success",
    message: validated.data.short_name
      ? `The enterprise is now named ${validated.data.short_name}`
      : "The enterprise is named after its primary unit again",
  };
}
