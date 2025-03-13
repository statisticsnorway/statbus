import { InfoBox } from "@/components/info-box";
import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import Link from "next/link";
import { setPrimaryEstablishment } from "../update-establishment-server-actions";
import { Button } from "@/components/ui/button";

export default async function PrimaryUnitInfo({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id),
    "establishment"
  );

  if (error) {
    throw new Error(error.message, { cause: error });
  }
  if (!hierarchy) {
    return;
  }

  const legalUnit = hierarchy.enterprise?.legal_unit?.find((lu) =>
    lu.establishment?.find((es) => es.id === parseInt(id))
  );

  const establishment =
    hierarchy.enterprise?.establishment?.find((es) => es.id === parseInt(id)) ||
    legalUnit?.establishment.find((es) => es.id === parseInt(id));

  if (!establishment) {
    return;
  }

  return (
    <div className="p-2 mt-2">
      {establishment.primary_for_legal_unit && legalUnit && (
        <InfoBox className="text-sm">
          <p>
            This is the primary establishment for the legal unit{" "}
            <Link className="underline" href={`/legal-units/${legalUnit.id}`}>
              {legalUnit.name}
            </Link>
          </p>
        </InfoBox>
      )}
      {establishment.primary_for_enterprise && (
        <InfoBox className="text-sm">
          <p>
            This is the primary establishment for the enterprise{" "}
            <Link
              className="underline"
              href={`/enterprises/${establishment.enterprise_id}`}
            >
              {establishment.name}
            </Link>
            .
          </p>
          <p>
            Changes you make to this establishment will affect the enterprise.
          </p>
        </InfoBox>
      )}

      {!establishment.primary_for_legal_unit &&
        establishment.legal_unit_id &&
        legalUnit && (
          <InfoBox className="text-sm bg-gray-100 border-grey-200 ">
            <form
              action={setPrimaryEstablishment.bind(null, establishment.id)}
              // className="p-4"
            >
              <div className="space-y-4 flex flex-col justify-center">
                <p>
                  This is <b>not</b> the primary establishment for the legal
                  unit{" "}
                  <Link
                    className="underline"
                    href={`/legal-units/${legalUnit.id}`}
                  >
                    {legalUnit.name}
                  </Link>
                  .
                </p>
                <Button type="submit" variant="outline">
                  Set as primary establishment
                </Button>
              </div>
            </form>
          </InfoBox>
        )}
    </div>
  );
}
