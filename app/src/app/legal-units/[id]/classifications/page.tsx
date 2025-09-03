import { Metadata } from "next";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import ClassificationsInfoForm from "./classifications-info-form";

export const metadata: Metadata = {
  title: "Legal Unit | Classifications",
};

export default async function LegalUnitClassificationsPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;

  const { id } = params;

  return (
    <DetailsPage
      title="Classifications"
      subtitle="Classifications such as activity categories, legal form and sector"
    >
      <ClassificationsInfoForm id={id} />
    </DetailsPage>
  );
}
