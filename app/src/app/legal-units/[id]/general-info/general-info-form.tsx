"use client";
import { Button } from "@/components/ui/button";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useFormState } from "react-dom";
import React from "react";
import { z } from "zod";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { SubmissionFeedbackDebugInfo } from "@/app/legal-units/components/submission-feedback-debug-info";
import { FormField } from "@/components/form/form-field";

export default function GeneralInfoForm({
  id,
  values,
}: {
  readonly id: string;
  readonly values: z.infer<typeof generalInfoSchema>;
}) {
  const [state, formAction] = useFormState(
    updateLegalUnit.bind(null, id, "general-info"),
    null
  );

  return (
    <form className="space-y-8" action={formAction}>
      <FormField
        label="Name"
        name="name"
        value={values.name}
        response={state}
      />
      {/* <FormField
        label="Tax Register ID"
        name="tax_ident"
        value={values.tax_ident}
        response={state}
      /> */}
      <SubmissionFeedbackDebugInfo state={state} />
      <Button type="submit">Update Legal Unit</Button>
    </form>
  );
}
