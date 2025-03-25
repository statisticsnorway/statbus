import { getLegalUnitById } from "@/components/statistical-unit-details/requests";
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

  const { legalUnit, error } = await getLegalUnitById(id);
  return (
    <HeaderSlot
      id={id}
      unit={legalUnit}
      error={error}
      className="border-legal_unit-200 bg-legal_unit-100"
    />
  );
}
