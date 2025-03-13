import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import TopologySlot from "@/components/statistical-unit-details/topology-slot";

export default async function LegalUnitLinksPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  return (
    <DetailsPage
      title="Links and external references"
      subtitle="Relationships (links) between units of different types within the SBR"
    >
      <TopologySlot unitId={parseInt(id)} unitType="legal_unit" />
    </DetailsPage>
  );
}
