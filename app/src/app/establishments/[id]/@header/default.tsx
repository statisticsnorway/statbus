"use client";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";
import { useParams } from "next/navigation";
import { useEstablishment } from "@/components/statistical-unit-details/use-unit-details";

export default function Slot() {
  const params = useParams();
  const id = params.id as string;
  const { establishment, isLoading, error } = useEstablishment(id);
  const hasLegalUnit = establishment?.legal_unit_id !== null;
  return (
    <HeaderSlot
      id={id}
      unit={establishment}
      error={error}
      loading={isLoading}
      className={
        hasLegalUnit
          ? "border-establishment-200 bg-establishment-100"
          : "border-informal-200 bg-informal-50"
      }
      unitType="establishment"
      unitTypeLabel="Establishment"
      hasLegalUnit={hasLegalUnit}
    />
  );
}
