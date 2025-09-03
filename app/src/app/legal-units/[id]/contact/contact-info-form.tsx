"use client";
import { Button } from "@/components/ui/button";
import React, { useActionState, useEffect, useState } from "react";
import { z } from "zod";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";
import { updateLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { FormField } from "@/components/form/form-field";
import { useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function ContactInfoForm({ id }: { readonly id: string }) {
  const [state, formAction] = useActionState(
    updateLegalUnit.bind(null, id, "contact-info"),
    null
  );
  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);
  const { data, isLoading, error } = useStatisticalUnitDetails(
    id,
    "legal_unit"
  );
  if (error || (!isLoading && !data)) {
    return <UnitNotFound />;
  }
  const legalUnit = data?.legal_unit?.[0];
  const postalLocation = legalUnit?.location?.find(
    (loc) => loc.type === "postal"
  );
  return (
    <div className="space-y-8">
      {isClient && (
        <>
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
            <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
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
            </div>
            <div className="grid lg:grid-cols-2 gap-4">
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
                label="Country"
                name="country_id"
                value={postalLocation?.country?.name}
                response={null}
              />
            </div>
          </form>
        </>
      )}
    </div>
  );
}
