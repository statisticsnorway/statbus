"use client";
import { FormField } from "@/components/form/form-field";
import { useBaseData } from "@/atoms/base-data";
import { EditableField } from "@/components/form/editable-field";
import { useActionState, useEffect, useState } from "react";
import { updateExternalIdent } from "@/app/legal-units/[id]/update-external-ident-server-action";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { updateEstablishment } from "../update-establishment-server-actions";
import { updateLocation } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useDetailsPageData } from "@/atoms/edits";
import { useSWRConfig } from "swr";
import { EditableFieldWithMetadata } from "@/components/form/editable-field-with-metadata";
import { SelectFormField } from "@/components/form/select-form-field";
import { EditableFieldGroup } from "@/components/form/editable-field-group";

export default function GeneralInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateEstablishment.bind(null, id),
    null
  );
  const [externalIdentState, externalIdentFormAction] = useActionState(
    updateExternalIdent.bind(null, id, "establishment"),
    null
  );
  const [locationState, locationAction] = useActionState(
    updateLocation.bind(null, id, "physical", "establishment"),
    null
  );
  const { externalIdentTypes } = useBaseData();
  const { regions, countries } = useDetailsPageData();

  const { data, isLoading, revalidate, error } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  const { mutate } = useSWRConfig();
  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);

  useEffect(() => {
    if (
      externalIdentState?.status === "success" ||
      state?.status === "success" ||
      locationState?.status === "success"
    ) {
      mutate((key) => Array.isArray(key) && key.includes(id));
    }
  }, [externalIdentState, state, locationState, mutate, id]);
  if (!isClient) {
    return <Loading />;
  }
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const establishment = data?.establishment?.[0];
  const physicalLocation = establishment?.location.find(
    (loc) => loc.type === "physical"
  );
  const regionOptions = regions.map((region) => ({
    value: region.id,
    label: `${region.code} ${region.name}`,
  }));
  const countriesOptions = countries.map((country) => ({
    value: country.id,
    label: `${country.name}`,
  }));

  return (
    <div className="space-y-4">
      <EditableFieldWithMetadata
        label="Name"
        fieldId="name"
        value={establishment?.name || ""}
        response={state}
        formAction={formAction}
      />
      <div className="grid lg:grid-cols-2 gap-4 p-3">
        {externalIdentTypes.map((type) => {
          const value = establishment?.external_idents[type.code];
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
        })}
      </div>
      <SubmissionFeedbackDebugInfo state={externalIdentState} />
      {physicalLocation && (
        <EditableFieldGroup
          key={physicalLocation.id}
          fieldGroupId="physical-location"
          title="Physical Location"
          action={locationAction}
          response={locationState}
        >
          {({ isEditing }) => (
            <>
              <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
                <FormField
                  name="address_part1"
                  label="Address Part 1"
                  value={physicalLocation?.address_part1}
                  response={locationState}
                  readonly={!isEditing}
                />
                <FormField
                  name="address_part2"
                  label="Address Part 2"
                  value={physicalLocation?.address_part2}
                  response={locationState}
                  readonly={!isEditing}
                />
                <FormField
                  name="address_part3"
                  label="Address Part 3"
                  value={physicalLocation?.address_part3}
                  response={locationState}
                  readonly={!isEditing}
                />
              </div>

              <div className="flex flex-col gap-4">
                <div className="grid lg:grid-cols-2 gap-4">
                  <FormField
                    name="postcode"
                    label="Post Code"
                    value={physicalLocation?.postcode}
                    response={null}
                    readonly={!isEditing}
                  />
                  <FormField
                    name="postplace"
                    label="Post Place"
                    value={physicalLocation?.postplace}
                    response={null}
                    readonly={!isEditing}
                  />
                  <SelectFormField
                    name="region_id"
                    label="Region"
                    readonly={!isEditing}
                    value={physicalLocation?.region?.id}
                    options={regionOptions}
                    placeholder="Select a region"
                  />
                  <SelectFormField
                    name="country_id"
                    label="Country"
                    value={physicalLocation?.country?.id}
                    options={countriesOptions}
                    readonly={!isEditing}
                    placeholder="Select a country"
                  />
                </div>
                <div className="grid lg:grid-cols-3 gap-4">
                  <FormField
                    readonly={!isEditing}
                    label="Latitude"
                    name="latitude"
                    value={physicalLocation?.latitude}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Longitude"
                    name="longitude"
                    value={physicalLocation?.longitude}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Altitude"
                    name="altitude"
                    value={physicalLocation?.altitude}
                    response={null}
                  />
                </div>
              </div>
            </>
          )}
        </EditableFieldGroup>
      )}
    </div>
  );
}
