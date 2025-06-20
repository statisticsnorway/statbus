"use client";
import React from "react";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { FormField } from "@/components/form/form-field";


export default function DemographicInfoForm({
  legalUnit,
}: {
  readonly legalUnit: LegalUnit;
}) {
  return (
    <form className="space-y-4">
      <FormField
        label="Status"
        name="status"
        value={legalUnit?.status?.name}
        response={null}
        readonly
      />
      <FormField
        label="Birth date"
        name="birth_date"
        value={legalUnit?.birth_date}
        response={null}
        readonly
      />
      <FormField
        label="Death date"
        name="death_date"
        value={legalUnit?.death_date}
        response={null}
        readonly
      />
      <SubmissionFeedbackDebugInfo state={null} />
    </form>
  );
}
