"use client";
import { useEnterprise } from "@/components/statistical-unit-details/use-unit-details";
import DataDump from "@/components/data-dump";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";

export default function InspectDump({ id }: { readonly id: string }) {
  const { enterprise, error } = useEnterprise(id);
  console.log(enterprise, error);

  if (error || !enterprise) {
    return <UnitNotFound />;
  }

  return <DataDump data={enterprise} />;
}
