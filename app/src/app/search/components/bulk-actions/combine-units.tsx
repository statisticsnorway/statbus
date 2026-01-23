"use client";
import { cn } from "@/lib/utils";
import { Combine } from "lucide-react";
import { CommandItem } from "@/components/ui/command";
import * as React from "react";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { logger } from "@/lib/client-logger";
import { useSelection, type StatisticalUnit } from "@/atoms/search";
import { CombineUnitsDialog } from "./combine-units-dialog";

export default function CombineUnits() {
  const router = useRouter();
  const { selected } = useSelection();
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  const legalUnit = selected.find(
    (unit: StatisticalUnit) => unit.unit_type === "legal_unit"
  );
  const enterprise = selected.find(
    (unit: StatisticalUnit) => unit.unit_type === "enterprise"
  );

  const isEligibleForCombination =
    selected.length === 2 && legalUnit && enterprise;

  const handleCombineUnits = async (validFrom: string, validTo: string) => {
    if (!legalUnit || !enterprise) {
      logger.error(
        "CombineUnits",
        "failed to set primary legal unit for enterprise due to missing legal unit or enterprise",
        { legalUnit, enterprise }
      );
      return;
    }

    try {
      const response = await fetch(
        `/api/legal-units/${legalUnit.unit_id}/primary`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            unit_id: enterprise.unit_id,
            valid_from: validFrom || null,
            valid_to: validTo || null,
          }),
        }
      );

      if (!response.ok) {
        logger.error(
          "CombineUnits",
          "failed to set primary legal unit for enterprise",
          { legalUnit, enterprise }
        );
        return;
      }

      setIsDialogOpen(false);
      router.push(`/enterprises/${enterprise.unit_id}`);
    } catch (e) {
      logger.error(
        "CombineUnits",
        "failed to set primary legal unit for enterprise",
        { error: e }
      );
    }
  };

  return (
    <>
      <CommandItem
        disabled={!isEligibleForCombination}
        onSelect={() => setIsDialogOpen(true)}
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

      {legalUnit && enterprise && (
        <CombineUnitsDialog
          isOpen={isDialogOpen}
          onOpenChange={setIsDialogOpen}
          legalUnit={legalUnit}
          enterprise={enterprise}
          onConfirm={handleCombineUnits}
        />
      )}
    </>
  );
}
