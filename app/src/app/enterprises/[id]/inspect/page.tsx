import DataDump from "@/components/data-dump";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getEnterpriseById } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";

export const metadata: Metadata = {
  title: "Enterprise | Inspect",
};

export default async function EnterpriseInspectionPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { enterprise, error } = await getEnterpriseById(id);

  if (error) {
    throw error;
  }

  if (!enterprise) {
    notFound();
  }

  return (
    <DetailsPage
      title="Data Dump"
      subtitle={`This section shows the raw data we have on ${enterprise.id}`}
    >
      <DataDump data={enterprise} />
    </DetailsPage>
  );
}
