"use client";
import { useEstablishment } from "@/components/statistical-unit-details/use-unit-details";
import DataDump from "@/components/data-dump";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function InspectDump({ id }: { readonly id: string }) {
  const { establishment, error } = useEstablishment(id);

  if (error || !establishment) {
    return <UnitNotFound />;
  }

  return <DataDump data={establishment} />;
}
