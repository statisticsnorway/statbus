"use client";
import { useLegalUnit } from "@/components/statistical-unit-details/use-unit-details";
import DataDump from "@/components/data-dump";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function InspectDump({ id }: { readonly id: string }) {
  const { legalUnit, error } = useLegalUnit(id);

  if (error || !legalUnit) {
    return <UnitNotFound />;
  }

  return <DataDump data={legalUnit} />;
}
