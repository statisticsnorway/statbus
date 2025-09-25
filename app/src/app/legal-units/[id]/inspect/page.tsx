import { Metadata } from "next";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import InspectDump from "./inspect";

export const metadata: Metadata = {
  title: "Legal Unit | Inspect",
};

export default async function LegalUnitInspectionPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Data Dump"
      subtitle={`This section shows the raw data we have on this legal unit`}
    >
      <InspectDump id={id} />
    </DetailsPage>
  );
}
