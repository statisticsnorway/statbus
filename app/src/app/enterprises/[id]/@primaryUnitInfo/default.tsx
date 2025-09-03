"use client";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { InfoBox } from "@/components/info-box";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import Link from "next/link";
import { useParams } from "next/navigation";

export default function PrimaryUnitInfo() {
  const params = useParams();
  const id = params.id as string;

  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "enterprise"
  );
  if (error) {
    throw new Error(error.message, { cause: error });
  }
  if (error || (!isLoading && !hierarchy)) {
    return (
      <div className="p-2 mt-2">
        <UnitNotFound />
      </div>
    );
  }

  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es) => es.primary_for_enterprise
  );
  const primaryUnit = primaryLegalUnit || primaryEstablishment;

  if (!primaryUnit) {
    return;
  }

  return (
    <div className="p-2 mt-2">
      <InfoBox className="text-sm">
        <p>
          The information for this enterprise is derived from the primary
          {primaryLegalUnit ? " legal unit" : " establishment"} &nbsp;
          <Link
            className="underline"
            href={`/${primaryLegalUnit ? "legal-units" : "establishments"}/${primaryUnit.id}`}
          >
            {primaryUnit.name}
          </Link>
          .
        </p>
        <p>
          If you need to update this information, update the primary
          {primaryLegalUnit ? " legal unit" : " establishment"}.
        </p>
      </InfoBox>
    </div>
  );
}
