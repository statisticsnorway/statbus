"use server";
import {createClient} from "@/lib/supabase/server";
import {revalidatePath} from "next/cache";
import {z} from "zod";
import {generalInfoSchema} from "@/app/legal-units/[id]/general-info/validation";
import {contactInfoSchema} from "@/app/legal-units/[id]/contact/validation";

export async function updateLegalUnit(id: string, schemaType: SchemaType, _prevState: any, formData: FormData): Promise<UpdateResponse> {
  "use server";
  const supabase = createClient()
  const schema = resolveSchemaByType(schemaType)
  const validatedFields = schema.safeParse(formData)

  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse form data",
      errors: validatedFields.error.issues.map(issue => ({
        path: issue.path.join("."),
        message: issue.message
      })),
    }
  }

  try {
    const response = await supabase
      .from('legal_unit')
      .update(validatedFields.data)
      .eq('id', id)

    if (response.status >= 400) {
      return {status: "error", message: response.statusText}
    }

    revalidatePath("/legal-units/[id]", "page")

  } catch (error) {
    return {status: "error", message: "failed to update legal unit"}
  }

  return {status: "success", message: "Legal unit successfully updated"}
}

type SchemaType = "general-info" | "contact-info";

function resolveSchemaByType(schemaType: SchemaType): z.Schema {
  switch (schemaType) {
    case "general-info":
      return generalInfoSchema;
    case "contact-info":
      return contactInfoSchema
    default:
      throw new Error(`Unknown schema type: ${schemaType}`)
  }
}
