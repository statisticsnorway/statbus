import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { InfoBox } from "@/components/info-box";
import logger from "@/lib/logger";

export default async function EstablishmentGeneralInfoPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { establishment, error } = await getEstablishmentById(id);

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  if (!establishment) {
    notFound();
  }

  async function setPrimary(id: number) {
    "use server";
    const client = createClient();
    const { error } = await client.rpc(
      "set_primary_establishment_for_legal_unit",
      { establishment_id: id }
    );

    if (error) {
      logger.error({ error }, "failed to set primary establishment");
      return;
    }

    return revalidatePath("/establishments/[id]", "page");
  }

  return (
    <DetailsPage
      title="General Info"
      subtitle="General information such as name, sector"
    >
      <p className="p-12 text-center text-sm">
        This section will show general information for {establishment.name}
      </p>

      {establishment.primary_for_legal_unit && (
        <InfoBox>
          <p>
            This is the primary establishment. Changes you make to this
            establishment will affect the legal unit.
          </p>
        </InfoBox>
      )}
      {!establishment.primary_for_legal_unit && (
        <form
          action={setPrimary.bind(null, establishment.id)}
          className="bg-gray-100 p-2"
        >
          <Button type="submit" variant="outline">
            Set as primary establishment
          </Button>
        </form>
      )}
    </DetailsPage>
  );
}
