"use server";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { createServerLogger } from "@/lib/server-logger";

export async function updateLegalUnit(
  id: string,
  schemaType: SchemaType,
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  "use server";
  const client = await createSupabaseSSRClient();
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

  try {
    const response = await client
      .from("legal_unit")
      .update(validatedFields.data)
      .eq("id", id);

    if (response.status >= 400) {
      return { status: "error", message: response.statusText };
    }

    revalidatePath("/legal-units/[id]", "page");
  } catch (error) {
    return { status: "error", message: "failed to update legal unit" };
  }

  return { status: "success", message: "Legal unit successfully updated" };
}

export async function setPrimaryLegalUnit(id: number) {
  "use server";
  const logger = await createServerLogger();
  const client = await createSupabaseSSRClient();
  const { error } = await client.rpc("set_primary_legal_unit_for_enterprise", {
    legal_unit_id: id,
  });

  if (error) {
    logger.error(error, "failed to set primary legal unit");
    return;
  }

  revalidatePath("/legal-units/[id]", "page");
}

type SchemaType = "general-info" | "contact-info";

function resolveSchemaByType(schemaType: SchemaType): z.Schema {
  switch (schemaType) {
    case "general-info":
      return generalInfoSchema;
    case "contact-info":
      return contactInfoSchema;
    default:
      throw new Error(`Unknown schema type: ${schemaType}`);
  }
}
