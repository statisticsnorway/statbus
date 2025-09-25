"use client";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import { FormField } from "@/components/form/form-field";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import {
  updateContact,
  updateLocation,
} from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useActionState, useEffect } from "react";
import { useDetailsPageData } from "@/atoms/edits";
import { EditableFieldGroup } from "@/components/form/editable-field-group";
import { SelectFormField } from "@/components/form/select-form-field";

export default function ContactInfoForm({ id }: { readonly id: string }) {
  const [locationState, locationAction] = useActionState(
    updateLocation.bind(null, id, "postal", "establishment"),
    null
  );
  const [contactState, contactAction] = useActionState(
    updateContact.bind(null, id, "establishment"),
    null
  );
  const { data, isLoading, error, revalidate } = useStatisticalUnitDetails(
    id,
    "establishment"
  );
  const { countries } = useDetailsPageData();
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
  const establishment = data?.establishment?.[0];
  const postalLocation = establishment?.location?.find(
    (loc) => loc.type === "postal"
  );
  const countriesOptions = countries.map((country) => ({
    value: country.id,
    label: `${country.name}`,
  }));
  return (
    <div className="space-y-8">
      <div className="flex flex-col gap-4">
        {establishment?.contact && (
          <EditableFieldGroup
            key={establishment?.contact?.id}
            fieldGroupId="contact-info"
            title="Communication"
            action={contactAction}
            response={contactState}
          >
            {({ isEditing }) => (
              <>
                <div className="grid lg:grid-cols-2 gap-4">
                  <FormField
                    readonly={!isEditing}
                    label="Email address"
                    name="email_address"
                    value={establishment?.contact?.email_address}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Web Address"
                    name="web_address"
                    value={establishment?.contact?.web_address}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Phone number"
                    name="phone_number"
                    value={establishment?.contact?.phone_number}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Landline"
                    name="landline"
                    value={establishment?.contact?.landline}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Mobile Number"
                    name="mobile_number"
                    value={establishment?.contact?.mobile_number}
                    response={null}
                  />
                  <FormField
                    readonly={!isEditing}
                    label="Fax Number"
                    name="fax_number"
                    value={establishment?.contact?.fax_number}
                    response={null}
                  />
                </div>
              </>
            )}
          </EditableFieldGroup>
        )}
      </div>
      {postalLocation && (
        <EditableFieldGroup
          key={postalLocation.id}
          fieldGroupId="postal-location"
          title="Postal Location"
          action={locationAction}
          response={locationState}
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
      )}
    </div>
  );
}