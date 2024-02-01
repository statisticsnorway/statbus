'use client';
import {Button} from "@/components/ui/button";
import {updateGeneralInfo} from "@/app/legal-units/[id]/general-info/action";
import {useFormState} from "react-dom";
import React from "react";
import {z} from "zod";
import {formSchema} from "@/app/legal-units/[id]/general-info/validation";
import {FormField} from "@/app/legal-units/components/form-field";
import {SubmissionFeedbackDebugInfo} from "@/app/legal-units/components/submission-feedback-debug-info";

export default function GeneralInfoForm({id, values}: {
  readonly id: string,
  readonly values: z.infer<typeof formSchema>
}) {
  const [state, formAction] = useFormState(updateGeneralInfo.bind(null, id), null)

  return (
    <form className="space-y-8" action={formAction}>
      <FormField label="Name" name="name" value={values.name} response={state}/>
      <FormField label="Tax Register ID" name="tax_reg_ident" value={values.tax_reg_ident} response={state}/>
      <SubmissionFeedbackDebugInfo state={state}/>
      <Button type="submit">Update Legal Unit</Button>
    </form>
  )
}
