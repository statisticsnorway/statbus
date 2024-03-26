"use client";
import { Button } from "@/components/ui/button";
import { useFormState } from "react-dom";
import React from "react";
import { z } from "zod";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { SubmissionFeedbackDebugInfo } from "@/app/legal-units/components/submission-feedback-debug-info";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { FormField } from "@/components/form/form-field";

export default function ContactInfoForm({
  id,
  values,
}: {
  readonly id: string;
  readonly values: z.infer<typeof contactInfoSchema>;
}) {
  const [state, formAction] = useFormState(
    updateLegalUnit.bind(null, id, "contact-info"),
    null
  );

  return (
    <form className="space-y-8" action={formAction}>
      <FormField
        label="Email address"
        name="email_address"
        value={values.email_address}
        response={state}
      />
      <FormField
        label="Telephone number"
        name="telephone_no"
        value={values.telephone_no}
        response={state}
      />
      <FormField
        label="Web Address"
        name="web_address"
        value={values.web_address}
        response={state}
      />
      <SubmissionFeedbackDebugInfo state={state} />
      <Button type="submit">Update Contact Information</Button>
    </form>
  );
}
