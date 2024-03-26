import { Metadata } from "next";
import { notFound } from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getLegalUnitById } from "@/components/statistical-unit-details/requests";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { setPrimaryLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";

export const metadata: Metadata = {
  title: "Legal Unit | General Info",
};

export default async function LegalUnitGeneralInfoPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { legalUnit, error } = await getLegalUnitById(id);

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!legalUnit) {
    notFound();
  }

  return (
    <DetailsPage
      title="General Info"
      subtitle="General information such as name, id, sector and primary activity"
    >
      <GeneralInfoForm values={legalUnit} id={id} />
      {legalUnit.primary_for_enterprise && (
        <InfoBox>
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
        <form
          action={setPrimaryLegalUnit.bind(null, legalUnit.id)}
          className="bg-gray-100 p-2"
        >
          <Button type="submit" variant="outline">
            Set as primary legal unit
          </Button>
        </form>
      )}
    </DetailsPage>
  );
}
