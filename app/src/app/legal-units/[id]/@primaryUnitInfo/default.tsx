import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { setPrimaryLegalUnit } from "../update-legal-unit-server-actions";

export default async function PrimaryUnitInfo({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "legal_unit"
  );
  if (error) {
    throw new Error(error.message, { cause: error });
  }

  const legalUnit = hierarchy?.enterprise?.legal_unit.find(
    (lu) => lu.id === parseInt(id, 10)
  );

  if (!legalUnit) {
    return;
  }

  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  return (
    <div className="p-2 mt-2">
      {legalUnit.primary_for_enterprise && (
        <InfoBox className="text-sm">
          <p>
            This legal unit is the primary legal unit for the enterprise &nbsp;
            <Link
              className="underline"
              href={`/enterprises/${legalUnit.enterprise_id}`}
            >
              {legalUnit.name}
            </Link>
            .
          </p>
          <p>Changes you make to this legal unit will affect the enterprise.</p>
        </InfoBox>
      )}
      {!legalUnit.primary_for_enterprise && (
        <div className="text-sm bg-gray-100 border-2 border-grey-200 ">
          <form
            action={setPrimaryLegalUnit.bind(null, legalUnit.id)}
            className="p-4"
          >
            <div className="space-y-6">
              <p>
                This legal unit is <b>not</b> the primary legal unit for the
                enterprise &nbsp;
                <Link
                  className="underline"
                  href={`/enterprises/${legalUnit.enterprise_id}`}
                >
                  {primaryLegalUnit?.name}
                </Link>
                .
              </p>
              <Button type="submit" variant="outline">
                Set as primary legal unit
              </Button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
