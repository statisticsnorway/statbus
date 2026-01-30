"use client";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { setPrimaryLegalUnit } from "../update-legal-unit-server-actions";
import { useParams } from "next/navigation";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { usePermission } from "@/atoms/auth";

export default function PrimaryUnitInfo() {
  const params = useParams();
  const id = params.id as string;
  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "legal_unit"
  );
  const { canEdit } = usePermission();
  if (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(errorMessage, { cause: error });
  }
  if (error || (!isLoading && !hierarchy)) {
    return (
      <div className="p-2 mt-2">
        <UnitNotFound />
      </div>
    );
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
              {canEdit && (
                <Button type="submit" variant="outline">
                  Set as primary legal unit
                </Button>
              )}
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
