"use client";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { DisplayFormField } from "@/components/form/display-field";

export default function ContactInfoForm({ id }: { readonly id: string }) {
  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "enterprise"
  );
  if (error || (!isLoading && !hierarchy)) {
    return <UnitNotFound />;
  }
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;
  const postalLocation = primaryUnit?.location?.find(
    (loc) => loc.type === "postal"
  );
  return (
    <div className="space-y-8">
      <form className="flex flex-col gap-4">
        <span className="font-medium">Communication</span>
        <div className="grid lg:grid-cols-2 gap-4">
          <DisplayFormField
            
            label="Email address"
            name="email_address"
            value={primaryUnit?.contact?.email_address}
            
          />
          <DisplayFormField
            
            label="Web Address"
            name="web_address"
            value={primaryUnit?.contact?.web_address}
            
          />
          <DisplayFormField
            
            label="Phone number"
            name="phone_number"
            value={primaryUnit?.contact?.phone_number}
            
          />
          <DisplayFormField
            
            label="Landline"
            name="landline"
            value={primaryUnit?.contact?.landline}
            
          />
          <DisplayFormField
            
            label="Mobile Number"
            name="mobile_number"
            value={primaryUnit?.contact?.mobile_number}
            
          />
          <DisplayFormField
            
            label="Fax Number"
            name="fax_number"
            value={primaryUnit?.contact?.fax_number}
            
          />
        </div>
      </form>
      <form className="flex flex-col gap-4">
        <span className="font-medium">Postal Location</span>
        <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
          <DisplayFormField
            
            label="Address part1"
            name="address_part1"
            value={postalLocation?.address_part1}
            
          />
          <DisplayFormField
            
            label="Address part2"
            name="address_part2"
            value={postalLocation?.address_part2}
            
          />
          <DisplayFormField
            
            label="Address part3"
            name="address_part3"
            value={postalLocation?.address_part3}
            
          />
        </div>
        <div className="grid lg:grid-cols-2 gap-4">
          <DisplayFormField
            
            label="Post code"
            name="postcode"
            value={postalLocation?.postcode}
            
          />
          <DisplayFormField
            
            label="Post place"
            name="postplace"
            value={postalLocation?.postplace}
            
          />
          <DisplayFormField
            
            label="Country"
            name="country_id"
            value={postalLocation?.country?.name}
            
          />
        </div>
      </form>
    </div>
  );
}
