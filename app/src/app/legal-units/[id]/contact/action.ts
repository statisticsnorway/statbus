"use server";
import {createClient} from "@/lib/supabase/server";
import {revalidatePath} from "next/cache";
import {UpdateResponse} from "@/app/legal-units/types";
import {formSchema} from "@/app/legal-units/[id]/contact/validation";

export async function updateContactInfo(id: string, _prevState: any, formData: FormData): Promise<UpdateResponse> {
    "use server";
    const supabase = createClient()
    const validatedFields = formSchema.safeParse(formData)

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

        revalidatePath("/legal-units/[id]/contact", "page")

    } catch (error) {
        return {status: "error", message: "failed to update legal unit"}
    }

    return {status: "success", message: "Legal unit successfully updated"}
}

