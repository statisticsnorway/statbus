import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";
import { FormField } from "@/components/form/form-field";

export const metadata: Metadata = {
  title: "Enterprise | Contact",
};

export default async function EnterpriseContactPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "enterprise"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!hierarchy) {
    notFound();
  }

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  if (!primaryUnit) {
    notFound();
  }

  const postalLocation = primaryUnit?.location?.find(
    (loc) => loc.type === "postal"
  );

  return (
    <DetailsPage
      title="Contact Info"
      subtitle="Contact information such as email, phone and postal address"
    >
      <div className="space-y-8">
        <form className="flex flex-col gap-4">
          <span className="font-medium">Communication</span>
          <div className="grid lg:grid-cols-2 gap-4">
            <FormField
              readonly
              label="Email address"
              name="email_address"
              value={primaryUnit?.contact?.email_address}
              response={null}
            />
            <FormField
              readonly
              label="Web Address"
              name="web_address"
              value={primaryUnit?.contact?.web_address}
              response={null}
            />
            <FormField
              readonly
              label="Phone number"
              name="phone_number"
              value={primaryUnit?.contact?.phone_number}
              response={null}
            />
            <FormField
              readonly
              label="Landline"
              name="landline"
              value={primaryUnit?.contact?.landline}
              response={null}
            />
            <FormField
              readonly
              label="Mobile Number"
              name="mobile_number"
              value={primaryUnit?.contact?.mobile_number}
              response={null}
            />
            <FormField
              readonly
              label="Fax Number"
              name="fax_number"
              value={primaryUnit?.contact?.fax_number}
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
    </DetailsPage>
  );
}
