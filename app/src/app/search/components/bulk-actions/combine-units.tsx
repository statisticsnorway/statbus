"use client";
import { cn } from "@/lib/utils";
import { Combine } from "lucide-react";
import { CommandItem } from "@/components/ui/command";
import * as React from "react";
import { useCartContext } from "@/app/search/cart-provider";
import { useRouter } from "next/navigation";

export default function CombineUnits() {
  const router = useRouter();
  const { selected } = useCartContext();

  const isEligibleForCombination =
    selected.length === 2 &&
    selected.find((unit) => unit.unit_type === "enterprise") &&
    selected.find((unit) => unit.unit_type === "legal_unit");

  const setPrimaryLegalUnitForEnterprise = async () => {
    const legalUnit = selected.find((unit) => unit.unit_type === "legal_unit");
    const enterprise = selected.find((unit) => unit.unit_type === "enterprise");

    if (!legalUnit || !enterprise) {
      console.error(
        "failed to set primary legal unit for enterprise due to missing legal unit or enterprise"
      );
      return;
    }

    try {
      const response = await fetch(
        `/api/legal-units/${legalUnit.unit_id}/primary`,
        {
          method: "POST",
          body: JSON.stringify(enterprise),
        }
      );

      if (!response.ok) {
        console.error("failed to set primary legal unit for enterprise");
        return;
      }

      router.push(`/enterprises/${enterprise.unit_id}`);
    } catch (e) {
      console.error("failed to set primary legal unit for enterprise", e);
    }
  };

  return (
    <CommandItem
      disabled={!isEligibleForCombination}
      onSelect={setPrimaryLegalUnitForEnterprise}
      className={cn(
        "flex-col items-start space-y-1",
        !isEligibleForCombination && "opacity-50"
      )}
    >
      <div className="flex items-center space-x-2">
        <Combine className="h-4 w-4" />
        <span>Combine units</span>
      </div>
      <span className="text-xs">One Legal Unit and one Enterprise</span>
    </CommandItem>
  );
}
