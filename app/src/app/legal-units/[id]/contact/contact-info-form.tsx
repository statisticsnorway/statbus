"use client";
import { Button } from "@/components/ui/button";
import React, { useActionState } from "react";
import { z } from "zod";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { FormField } from "@/components/form/form-field";

export default function ContactInfoForm({
  id,
  legalUnit,
}: {
  readonly id: string;
  readonly legalUnit: LegalUnit;
}) {
  const [state, formAction] = useActionState(
    updateLegalUnit.bind(null, id, "contact-info"),
    null
  );
  const postalLocation = legalUnit?.location?.find(
    (loc) => loc.type === "postal"
  );
return (
  <div className="space-y-8">
    <form className="flex flex-col gap-4">
      <span className="font-medium">Communication</span>
      <div className="grid lg:grid-cols-2 gap-4">
        <FormField
          readonly
          label="Email address"
          name="email_address"
          value={legalUnit?.contact?.email_address}
          response={null}
        />
        <FormField
          readonly
          label="Web Address"
          name="web_address"
          value={legalUnit?.contact?.web_address}
          response={null}
        />
        <FormField
          readonly
          label="Phone number"
          name="phone_number"
          value={legalUnit?.contact?.phone_number}
          response={null}
        />
        <FormField
          readonly
          label="Landline"
          name="landline"
          value={legalUnit?.contact?.landline}
          response={null}
        />
        <FormField
          readonly
          label="Mobile Number"
          name="mobile_number"
          value={legalUnit?.contact?.mobile_number}
          response={null}
        />
        <FormField
          readonly
          label="Fax Number"
          name="fax_number"
          value={legalUnit?.contact?.fax_number}
          response={null}
        />
      </div>
    </form>
    <form className="flex flex-col gap-4">
      <span className="font-medium">Postal Location</span>
      <div className="grid grid-cols-2 gap-4">
        <FormField
          readonly
          label="Region"
          name="region_id"
          value={
            postalLocation?.region
              ? `${postalLocation.region.code} ${postalLocation.region.name}`
              : null
          }
          response={null}
        />
        <FormField
          readonly
          label="Country"
          name="country_id"
          value={postalLocation?.country?.name}
          response={null}
        />
        <FormField
          readonly
          label="Address part1"
          name="address_part1"
          value={postalLocation?.address_part1}
          response={null}
        />
        <FormField
          readonly
          label="Address part2"
          name="address_part2"
          value={postalLocation?.address_part2}
          response={null}
        />
        <FormField
          readonly
          label="Address part3"
          name="address_part3"
          value={postalLocation?.address_part3}
          response={null}
        />
        <FormField
          readonly
          label="Post code"
          name="postcode"
          value={postalLocation?.postcode}
          response={null}
        />
        <FormField
          readonly
          label="Post place"
          name="postplace"
          value={postalLocation?.postplace}
          response={null}
        />
        <FormField
          readonly
          label="Latitude"
          name="latitude"
          value={postalLocation?.latitude}
          response={null}
        />
        <FormField
          readonly
          label="Longitude"
          name="longitude"
          value={postalLocation?.longitude}
          response={null}
        />
        <FormField
          readonly
          label="Altitude"
          name="altitude"
          value={postalLocation?.altitude}
          response={null}
        />
      </div>
    </form>
  </div>
);
}
