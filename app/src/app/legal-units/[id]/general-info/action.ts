"use server";
import {createClient} from "@/lib/supabase/server";
import {formSchema} from "@/app/legal-units/[id]/general-info/validation";
import {revalidatePath} from "next/cache";

export type State = {
    status: "success";
    message: string;
} | {
    status: "error";
    message: string;
    errors?: Array<{
        path: string;
        message: string;
    }>;
} | null;

export async function updateGeneralInfo(id: string, _prevState: any, formData: FormData): Promise<State> {
    "use server";
    const supabase = createClient()
    const validatedFields = formSchema.safeParse(formData)

    if (!validatedFields.success) {
        console.error('failed to parse form data', validatedFields.error)
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
            console.error('failed to update legal unit general info', response.error)
            return {status: "error", message: response.statusText}
        }

        revalidatePath("/legal-units/[id]/general-info", "page")

    } catch (error) {
        return {status: "error", message: "failed to update legal unit general info"}
    }

    return {status: "success", message: "Legal unit general info successfully updated"}
}

