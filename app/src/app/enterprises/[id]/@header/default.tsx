import { getStatisticalUnitHierarchy } from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { hierarchy, error } = await getStatisticalUnitHierarchy(
    parseInt(id, 10),
    "enterprise"
  );
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu) => lu.primary_for_enterprise
  );
  const establishment = hierarchy?.enterprise?.establishment?.[0];
  if (!primaryLegalUnit && !establishment) {
    throw new Error("No primary legal unit or establishment found");
  }
  return (
    <HeaderSlot
      id={id}
      unit={primaryLegalUnit || establishment}
      error={error}
      className="border-enterprise-200 bg-enterprise-100"
    />
  );
}
