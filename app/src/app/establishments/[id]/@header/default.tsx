import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot({
  params: { id },
}: {
  readonly params: { id: string };
}) {
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
