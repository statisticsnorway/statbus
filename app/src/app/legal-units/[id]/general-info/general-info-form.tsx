'use client';
import {Input} from "@/components/ui/input";
import {Button} from "@/components/ui/button";
import type {State} from "@/app/legal-units/[id]/general-info/action";
import {updateGeneralInfo} from "@/app/legal-units/[id]/general-info/action";
import {useFormState} from "react-dom";
import React from "react";
import {Label} from "@/components/ui/label";
import {cn} from "@/lib/utils";
import {z} from "zod";
import {formSchema} from "@/app/legal-units/[id]/general-info/validation";

export default function GeneralInfoForm({id, values}: {
    id: string,
    values: z.infer<typeof formSchema>
}) {
    const [state, formAction] = useFormState(updateGeneralInfo.bind(null, id), null)

    return (
        <form className="space-y-8" action={formAction}>
            <FormField label="Name" name="name" value={values.name} state={state}/>
            <FormField label="Tax Register ID" name="tax_reg_ident" value={values.tax_reg_ident} state={state}/>
            <SubmissionFeedbackDebugInfo state={state}/>
            <Button type="submit">Update Legal Unit</Button>
        </form>
    )
}

function FormField({label, name, value, state}: {
    label: string,
    name: string,
    value: string | null,
    state: State
}) {
    const error = state?.status === "error" ? state?.errors?.find(a => a.path === name) : null
    return (
        <div>
            <Label className="space-y-2 block">
                <span className="uppercase text-xs text-gray-600">{label}</span>
                <Input type="text" name={name} defaultValue={value ?? ""} autoComplete="off"/>
            </Label>
            {error ? (<span className="mt-2 block text-sm text-red-500">{error?.message}</span>) : null}
        </div>
    )
}

function SubmissionFeedbackDebugInfo({state}: {
    state: State
}) {
    return state?.status ? (
        <small className="block">
            <pre
                className={cn("mt-2 rounded-md bg-red-100 p-4", state.status === "success" ? "bg-green-100" : "bg-red-100")}>
                <code className="text-xs">{JSON.stringify(state, null, 2)}</code>
            </pre>
        </small>
    ) : null
}
