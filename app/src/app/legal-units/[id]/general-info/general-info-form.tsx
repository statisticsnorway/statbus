"use client";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import React, { useActionState, useEffect, useState } from "react";
import { z } from "zod";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { FormField } from "@/components/form/form-field";
import { useBaseData } from "@/atoms/base-data";
import { updateExternalIdent } from "@/app/legal-units/[id]/update-external-ident-server-action";
import { Tables } from "@/lib/database.types";
import { EditableField } from "@/components/form/editable-field";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function GeneralInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateLegalUnit.bind(null, id, "general-info"),
    null
  );
  const [externalIdentState, externalIdentFormAction] = useActionState(
    updateExternalIdent.bind(null, id, "legal_unit"),
    null
  );
  const { externalIdentTypes } = useBaseData();

  const { data, isLoading, revalidate, error } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );

  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);

  useEffect(() => {
    if (externalIdentState?.status === "success") {
      revalidate();
    }
  }, [externalIdentState, revalidate]);
  if (!isClient) {
    return <Loading />;
  }
    if (!isLoading && !data) {
      return <UnitNotFound />;
    }
  const legalUnit = data?.legal_unit?.[0];

  const physicalLocation = legalUnit?.location.find(
    (loc) => loc.type === "physical"
  );
  return (
    <div className="space-y-8">
      <FormField
        label="Name"
        name="name"
        value={legalUnit?.name}
        response={null}
        readonly
      />
      <div className="grid lg:grid-cols-2 gap-4">
        {externalIdentTypes.map(
          (type: Tables<"external_ident_type_active">) => {
            const value = legalUnit?.external_idents[type.code];
            return (
              <EditableField
                key={type.code}
                fieldId={`${type.code}`}
                label={type.name ?? type.code!}
                value={value}
                response={externalIdentState}
                formAction={externalIdentFormAction}
              />
            );
          }
        )}
      </div>
      <SubmissionFeedbackDebugInfo state={externalIdentState} />
      <form className="flex flex-col gap-4">
        <span className="font-medium">Physical Location</span>
        <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
          <FormField
            name="address_part1"
            label="Address Part 1"
            value={physicalLocation?.address_part1}
            response={null}
            readonly
          />
          <FormField
            name="address_part2"
            label="Address Part 2"
            value={physicalLocation?.address_part2}
            response={null}
            readonly
          />
          <FormField
            name="address_part3"
            label="Address Part 3"
            value={physicalLocation?.address_part3}
            response={null}
            readonly
          />
        </div>
        <div className="grid lg:grid-cols-2 gap-4">
          <FormField
            name="postcode"
            label="Post Code"
            value={physicalLocation?.postcode}
            response={null}
            readonly
          />
          <FormField
            name="postplace"
            label="Post Place"
            value={physicalLocation?.postplace}
            response={null}
            readonly
          />
          <FormField
            name="region_id"
            label="Region"
            value={
              physicalLocation?.region
                ? `${physicalLocation.region.code} ${physicalLocation.region.name}`
                : null
            }
            response={null}
            readonly
          />
          <FormField
            name="country_id"
            label="Country"
            value={physicalLocation?.country?.name}
            response={null}
            readonly
          />
        </div>
        <div className="grid lg:grid-cols-3 gap-4">
          <FormField
            readonly
            label="Latitude"
            name="latitude"
            value={physicalLocation?.latitude}
            response={null}
          />
          <FormField
            readonly
            label="Longitude"
            name="longitude"
            value={physicalLocation?.longitude}
            response={null}
          />
          <FormField
            readonly
            label="Altitude"
            name="altitude"
            value={physicalLocation?.altitude}
            response={null}
          />
        </div>
      </form>
    </div>
  );
}
