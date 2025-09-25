import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import TopologySlot from "@/components/statistical-unit-details/topology-slot";

export default async function LegalUnitLinksPage(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  return (
    <DetailsPage
      title="Links and external references"
      subtitle="Relationships (links) between units of different types within the SBR"
    >
      <TopologySlot unitId={id} unitType="legal_unit" />
    </DetailsPage>
  );
}
