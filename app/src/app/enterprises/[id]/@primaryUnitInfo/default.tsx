import { InfoBox } from "@/components/info-box";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import Link from "next/link";

export default async function PrimaryUnitInfo(
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
    return;
  }
  const primaryLegalUnit = hierarchy.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy.enterprise?.establishment?.find(
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
