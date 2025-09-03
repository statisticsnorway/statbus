"use client";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";
import { useParams } from "next/navigation";
import { useLegalUnit } from "@/components/statistical-unit-details/use-unit-details";

export default function Slot() {
  const params = useParams();
  const id = params.id as string;
  const { legalUnit, isLoading, error } = useLegalUnit(id);
  return (
    <HeaderSlot
      id={id}
      unit={legalUnit}
      error={error}
      loading={isLoading}
      className="border-legal_unit-200 bg-legal_unit-100"
    />
  );
}
