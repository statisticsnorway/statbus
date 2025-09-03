import { Metadata } from "next";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
export const metadata: Metadata = {
  title: "Legal Unit | General Info",
};
export default async function LegalUnitGeneralInfoPage(props: {
  readonly params: Promise<{ id: string }>;
}) {
  const params = await props.params;
  const { id } = params;
  return (
    <DetailsPage
      title="Identification"
      subtitle="Identification information such as name, id(s) and physical address"
    >
      <GeneralInfoForm id={id} />
    </DetailsPage>
  );
}
