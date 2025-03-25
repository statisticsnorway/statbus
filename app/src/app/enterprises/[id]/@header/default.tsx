import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "enterprise"
  );
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu: LegalUnit) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es: Establishment) => es.primary_for_enterprise
  );
  return (
    <HeaderSlot
      id={id}
      unit={primaryLegalUnit || primaryEstablishment}
      error={error}
      className="border-enterprise-200 bg-enterprise-100"
    />
  );
}
