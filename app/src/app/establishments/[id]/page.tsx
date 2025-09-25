import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { Metadata } from "next";
import GeneralInfoForm from "./general-info/general-info-form";

export const metadata: Metadata = {
  title: "Establishment | General Info",
};

export default async function EstablishmentGeneralInfoPage(props: {
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
