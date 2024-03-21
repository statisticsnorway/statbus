import { Metadata } from "next";
import { notFound } from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { getLegalUnitById } from "@/components/statistical-unit-details/requests";
import { InfoBox } from "@/components/info-box";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { Button } from "@/components/ui/button";
import { createServerLogger } from "@/lib/logger";

export const metadata: Metadata = {
  title: "Legal Unit | General Info",
};

export default async function LegalUnitGeneralInfoPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { legalUnit, error } = await getLegalUnitById(id);
  const logger = await createServerLogger();

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!legalUnit) {
    notFound();
  }

  async function setPrimary(id: number) {
    "use server";
    const client = createClient();
    const { error } = await client.rpc(
      "set_primary_legal_unit_for_enterprise",
      { legal_unit_id: id }
    );

    if (error) {
      logger.error(error, "failed to set primary legal unit");
      return;
    }

    return revalidatePath("/legal-units/[id]", "page");
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
          action={setPrimary.bind(null, legalUnit.id)}
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
