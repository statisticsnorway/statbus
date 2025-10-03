"use client";
import { Button } from "@/components/ui/button";
import React, { useActionState, useEffect, useState } from "react";
import { z } from "zod";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import {
  updateContact,
  updateLocation,
} from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { FormField } from "@/components/form/form-field";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { EditableFieldGroup } from "@/components/form/editable-field-group";
import { useDetailsPageData } from "@/atoms/edits";
import { SelectFormField } from "@/components/form/select-form-field";

export default function ContactInfoForm({ id }: { readonly id: string }) {
  const [locationState, locationAction] = useActionState(
    updateLocation.bind(null, id, "postal", "legal_unit"),
    null
  );
  const [contactState, contactAction] = useActionState(
    updateContact.bind(null, id, "legal_unit"),
    null
  );
  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);
  const { countries } = useDetailsPageData();
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );

  useEffect(() => {
    if (
      locationState?.status === "success" ||
      contactState?.status === "success"
    ) {
      revalidate();
    }
  }, [contactState, locationState, revalidate]);
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const legalUnit = data?.legal_unit?.[0];
  const postalLocation = legalUnit?.location?.find(
    (loc) => loc.type === "postal"
  );
  const countriesOptions = countries.map((country) => ({
    value: country.id,
    label: `${country.name}`,
  }));
  return (
    <div className="space-y-2">
      <div>
          <EditableFieldGroup
            key={legalUnit?.contact?.id}
            fieldGroupId="contact-info"
            title="Communication"
            action={contactAction}
            response={contactState}
            metadata={legalUnit?.contact}
          >
            {({ isEditing }) => (
              <div className="grid lg:grid-cols-2 gap-4">
                <FormField
                  readonly={!isEditing}
                  label="Email address"
                  name="email_address"
                  value={legalUnit?.contact?.email_address}
                  response={null}
                />
                <FormField
                  readonly={!isEditing}
                  label="Web Address"
                  name="web_address"
                  value={legalUnit?.contact?.web_address}
                  response={null}
                />
                <FormField
                  readonly={!isEditing}
                  label="Phone number"
                  name="phone_number"
                  value={legalUnit?.contact?.phone_number}
                  response={null}
                />
                <FormField
                  readonly={!isEditing}
                  label="Landline"
                  name="landline"
                  value={legalUnit?.contact?.landline}
                  response={null}
                />
                <FormField
                  readonly={!isEditing}
                  label="Mobile Number"
                  name="mobile_number"
                  value={legalUnit?.contact?.mobile_number}
                  response={null}
                />
                <FormField
                  readonly={!isEditing}
                  label="Fax Number"
                  name="fax_number"
                  value={legalUnit?.contact?.fax_number}
                  response={null}
                />
              </div>
            )}
          </EditableFieldGroup>
      </div>
        <EditableFieldGroup
          key={postalLocation?.id}
          fieldGroupId="postal-location"
          title="Postal Location"
          action={locationAction}
          response={locationState}
          metadata={postalLocation}
        >
          {({ isEditing }) => (
            <>
              <div className="flex flex-col gap-4">
                <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
                  <FormField
                    readonly={!isEditing}
                    label="Address part1"
                    name="address_part1"
                    value={postalLocation?.address_part1}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Address part2"
                    name="address_part2"
                    value={postalLocation?.address_part2}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Address part3"
                    name="address_part3"
                    value={postalLocation?.address_part3}
                    response={null}
                  />
                </div>
                <div className="grid lg:grid-cols-2 gap-4">
                  <FormField
                    readonly={!isEditing}
                    label="Post code"
                    name="postcode"
                    value={postalLocation?.postcode}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Post place"
                    name="postplace"
                    value={postalLocation?.postplace}
                    response={null}
                  />
                  <SelectFormField
                    readonly={!isEditing}
                    label="Country"
                    name="country_id"
                    value={postalLocation?.country?.id}
                    options={countriesOptions}
                    placeholder="Select a country"
                  />
                </div>
              </div>
            </>
          )}
        </EditableFieldGroup>
    </div>
  );
}
