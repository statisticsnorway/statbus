"use client";
import HeaderSlot from "@/components/statistical-unit-details/header-slot";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { useParams } from "next/navigation";

export default function Slot() {
  const params = useParams();
  const id = params.id as string;

  const { hierarchy, isLoading, error } = useStatisticalUnitHierarchy(
    id,
    "enterprise"
  );
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find(
    (lu: LegalUnit) => lu.primary_for_enterprise
  );
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find(
    (es: Establishment) => es.primary_for_enterprise
  );
  const informal =
    hierarchy &&
    (!hierarchy.enterprise?.legal_unit ||
      hierarchy.enterprise.legal_unit.length === 0);
  return (
    <HeaderSlot
      id={id}
      unit={primaryLegalUnit || primaryEstablishment}
      error={error}
      loading={isLoading}
      className={
        informal
          ? "border-informal-400 bg-informal-300"
          : "border-enterprise-200 bg-enterprise-100"
      }
    />
  );
}
