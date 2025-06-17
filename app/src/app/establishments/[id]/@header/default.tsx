import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";

export default async function Slot(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const { id } = params;

  const { establishment, error } = await getEstablishmentById(id);
  const informal = establishment?.legal_unit_id === null;
  return (
    <HeaderSlot
      id={id}
      unit={establishment}
      error={error}
      className={
        informal
          ? "border-informal-200 bg-informal-50"
          : "border-establishment-200 bg-establishment-100"
      }
    />
  );
}
