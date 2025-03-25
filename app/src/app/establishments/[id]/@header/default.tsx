import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
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

  const { establishment, error } = await getEstablishmentById(id);
  return (
    <HeaderSlot
      id={id}
      unit={establishment}
      error={error}
      className="border-establishment-200 bg-establishment-100"
    />
  );
}
