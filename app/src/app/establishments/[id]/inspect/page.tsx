import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { Metadata } from "next";
import InspectDump from "./inspect";

export const metadata: Metadata = {
  title: "Establishment | Inspect",
};

export default async function EstablishmentInspectionPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Data Dump"
      subtitle={`This section shows the raw data we have on this establishment`}
    >
      <InspectDump id={id} />
    </DetailsPage>
  );
}
