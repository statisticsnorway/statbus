import DataDump from "@/components/data-dump";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";

export const metadata: Metadata = {
  title: "Establishment | Inspect",
};

export default async function EstablishmentInspectionPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { establishment, error } = await getEstablishmentById(id);

  if (error) {
    throw error;
  }

  if (!establishment) {
    notFound();
  }

  return (
    <DetailsPage
      title="Data Dump"
      subtitle={`This section shows the raw data we have on ${establishment.name}`}
    >
      <DataDump data={establishment} />
    </DetailsPage>
  );
}
