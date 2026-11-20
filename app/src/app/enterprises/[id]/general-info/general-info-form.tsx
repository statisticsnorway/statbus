"use client";
import { useActionState } from "react";
import Link from "next/link";
import { useSWRConfig } from "swr";
import { useBaseData } from "@/atoms/base-data";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import Loading from "@/components/statistical-unit-details/loading";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { DisplayFormField } from "@/components/form/display-field";
import { EditableField } from "@/components/form/editable-field";
import { useClientReady } from "@/hooks/use-client-ready";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { derivedEnterpriseName, enterpriseName } from "@/lib/enterprise-name";
import { updateEnterpriseShortName } from "../update-enterprise-server-actions";

export default function GeneralInfoForm({ id }: { readonly id: string }) {
  const { externalIdentTypes } = useBaseData();
  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "enterprise"
  );
  const [shortNameState, shortNameAction] = useActionState(
    updateEnterpriseShortName.bind(null, id),
    null
  );
  const { mutate } = useSWRConfig();
  // The header, this page and search read the enterprise's name; refetch them all.
  useGuardedEffect(
    () => {
      if (shortNameState?.status === "success") {
        mutate((key) => Array.isArray(key) && key.includes(id));
      }
    },
    [shortNameState, mutate, id],
    "EnterpriseGeneralInfoForm:revalidateAfterShortName"
  );
  const isClient = useClientReady();

  if (!isClient) {
    return <Loading />;
  }
  if (error || (!isLoading && !hierarchy)) {
    return <UnitNotFound />;
  }

  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const unit = primaryLegalUnit || primaryEstablishment;
  const physicalLocation = unit?.location?.find(
    (loc) => loc.type === "physical"
  );

  return (
    <div className="space-y-8">
      <div className="flex flex-col gap-8">
        <div className="flex flex-col gap-1">
          <DisplayFormField
            label="Name"
            name="name"
            value={
              hierarchy?.enterprise
                ? enterpriseName(hierarchy.enterprise)
                : unit?.name
            }
          />
          {/* With a short name set, the Name above differs from the primary unit's; name it for reference. */}
          {hierarchy?.enterprise?.short_name?.trim() && unit && (
            <p className="text-xs text-gray-500">
              The primary {primaryLegalUnit ? "legal unit" : "establishment"} is
              called{" "}
              <Link
                className="underline"
                href={`/${primaryLegalUnit ? "legal-units" : "establishments"}/${unit.id}`}
              >
                {unit.name}
              </Link>
              .
            </p>
          )}
        </div>
        <div className="flex flex-col gap-1">
          <EditableField
            fieldId="short_name"
            label="Short name"
            value={hierarchy?.enterprise?.short_name ?? null}
            placeholder={
              hierarchy?.enterprise
                ? (derivedEnterpriseName(hierarchy.enterprise) ?? undefined)
                : undefined
            }
            maxLength={16}
            formAction={shortNameAction}
            response={shortNameState}
          />
          <p className="text-xs text-gray-500">
            The name this enterprise goes by everywhere, up to 16 characters.
            Empty: it is named after its primary{" "}
            {primaryLegalUnit ? "legal unit" : "establishment"}.
          </p>
        </div>
        <div className={"grid gap-4 grid-cols-2"}>
          {externalIdentTypes.map((type) => {
            const value = unit?.external_idents[type.code];
            return (
              <DisplayFormField
                key={type.code}
                label={type.name ?? type.code!}
                name={`external_idents.${type.code}`}
                value={value}
              />
            );
          })}
        </div>
      </div>
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-4">
          <span className="font-medium">Physical Location</span>

          <div className="grid lg:grid-cols-2 gap-4 *:col-start-1">
            <DisplayFormField
              name="address_part1"
              label="Address Part 1"
              value={physicalLocation?.address_part1}
            />
            <DisplayFormField
              name="address_part2"
              label="Address Part 2"
              value={physicalLocation?.address_part2}
            />
            <DisplayFormField
              name="address_part3"
              label="Address Part 3"
              value={physicalLocation?.address_part3}
            />
          </div>
          <div className="grid lg:grid-cols-2 gap-4">
            <DisplayFormField
              name="postcode"
              label="Post Code"
              value={physicalLocation?.postcode}
            />
            <DisplayFormField
              name="postplace"
              label="Post Place"
              value={physicalLocation?.postplace}
            />
            <DisplayFormField
              name="region_id"
              label="Region"
              value={
                physicalLocation?.region
                  ? `${physicalLocation.region.code} ${physicalLocation.region.name}`
                  : null
              }
            />
            <DisplayFormField
              name="country_id"
              label="Country"
              value={physicalLocation?.country?.name}
            />
          </div>
          <div className="grid lg:grid-cols-3 gap-4">
            <DisplayFormField
              label="Latitude"
              name="latitude"
              value={physicalLocation?.latitude}
            />
            <DisplayFormField
              label="Longitude"
              name="longitude"
              value={physicalLocation?.longitude}
            />
            <DisplayFormField
              label="Altitude"
              name="altitude"
              value={physicalLocation?.altitude}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
