"use client";
import { useBaseData } from "@/app/BaseDataClient";
import { FormField } from "@/components/form/form-field";

export default function GeneralInfoForm({
  unit,
}: {
  readonly unit: LegalUnit | Establishment;
}) {
  const { externalIdentTypes } = useBaseData();

  const physicalLocation = unit.location.find((loc) => loc.type === "physical");

  return (
    <div className="space-y-8">
      <form className="flex flex-col gap-4">
        <FormField
          readonly
          label="Name"
          name="name"
          value={unit.name}
          response={null}
        />
        <div className={"grid gap-4 grid-cols-2"}>
          {externalIdentTypes.map((type) => {
            const value = unit.external_idents[type.code];
            return (
              <FormField
                readonly
                key={type.code}
                label={type.name ?? type.code!}
                name={`external_idents.${type.code}`}
                value={value}
                response={null}
              />
            );
          })}
        </div>
      </form>
      <form className="flex flex-col gap-4">
        <div className="flex flex-col gap-4">
          <span className="font-medium">Physical Location</span>

          <div className="grid lg:grid-cols-2 gap-4">
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
        </div>
      </form>
    </div>
  );
}
