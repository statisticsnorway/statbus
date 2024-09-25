"use client";
import { Button } from "@/components/ui/button";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useFormState } from "react-dom";
import React from "react";
import { z } from "zod";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { SubmissionFeedbackDebugInfo } from "@/app/legal-units/components/submission-feedback-debug-info";
import { FormField } from "@/components/form/form-field";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

export default function GeneralInfoForm({
  id,
  legal_unit,
}: {
  readonly id: string;
  readonly legal_unit: LegalUnit;
}) {
  const [state, formAction] = useFormState(
    updateLegalUnit.bind(null, id, "general-info"),
    null
  );
  const { externalIdentTypes } = useCustomConfigContext();

  return (
    <form className="space-y-8" action={formAction}>
      <FormField
        label="Name"
        name="name"
        value={legal_unit.name}
        response={state}
      />
      {externalIdentTypes.map((type) => {
        const value = legal_unit.external_idents[type.code];
        if (value) {
          return (
            <FormField
              readonly
              key={type.code}
              label={type.name ?? type.code}
              name={`external_idents.${type.code}`}
              value={value}
              response={state}
            />
          );
        }
        return null; // Skip rendering if there's no value
      })}

      <SubmissionFeedbackDebugInfo state={state} />
      <Button type="submit">Update Legal Unit</Button>
    </form>
  );
}
