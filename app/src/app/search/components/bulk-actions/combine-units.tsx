"use client";
import { cn } from "@/lib/utils";
import { Combine } from "lucide-react";
import { CommandItem } from "@/components/ui/command";
import * as React from "react";
import { useRouter } from "next/navigation";
import logger from "@/lib/client-logger";
import { useSelection } from "@/atoms/hooks"; // Changed to Jotai hook

export default function CombineUnits() {
  const router = useRouter();
  const { selected } = useSelection(); // Use Jotai hook

  const isEligibleForCombination =
    selected.length === 2 &&
    selected.find((unit) => unit.unit_type === "enterprise") &&
    selected.find((unit) => unit.unit_type === "legal_unit");

  const setPrimaryLegalUnitForEnterprise = async () => {
    const legalUnit = selected.find((unit) => unit.unit_type === "legal_unit");
    const enterprise = selected.find((unit) => unit.unit_type === "enterprise");

    if (!legalUnit || !enterprise) {
      logger.error(
        { legalUnit, enterprise },
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
        logger.error(
          { legalUnit, enterprise },
          "failed to set primary legal unit for enterprise"
        );
        return;
      }

      router.push(`/enterprises/${enterprise.unit_id}`);
    } catch (e) {
      logger.error(e, "failed to set primary legal unit for enterprise");
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
