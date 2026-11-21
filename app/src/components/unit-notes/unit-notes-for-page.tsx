"use client";

import { useParams, usePathname } from "next/navigation";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { UnitNotesBox } from "./unit-notes-box";
import { primaryChain } from "./primary-chain";
import type { NotesUnitColumn } from "./unit-notes";

type ChainUnitType = "enterprise" | "legal_unit" | "establishment";

const CHAIN_BY_SEGMENT: Record<string, { column: NotesUnitColumn; unitType: ChainUnitType }> = {
  "legal-units": { column: "legal_unit_id", unitType: "legal_unit" },
  establishments: { column: "establishment_id", unitType: "establishment" },
  enterprises: { column: "enterprise_id", unitType: "enterprise" },
};

/**
 * The notes box for the unit whose pages these are, named by the URL
 * (/legal-units/29/...): the notes of its primary chain (64ae2w). A power
 * group is not on that chain and shows its own note alone.
 */
export function UnitNotesForPage() {
  const params = useParams();
  const pathname = usePathname();
  const segment = pathname?.split("/")[1] ?? "";
  const id = (params?.id as string | undefined) ?? "";
  const unitId = parseInt(id, 10);
  if (!Number.isFinite(unitId)) return null;
  if (segment === "power-groups") {
    return (
      <UnitNotesBox
        chain={[{ column: "power_group_id", id: unitId, name: "", kind: "Power group", href: pathname ?? "", current: true }]}
      />
    );
  }
  const unit = CHAIN_BY_SEGMENT[segment];
  return unit ? <ChainNotes id={id} unitId={unitId} column={unit.column} unitType={unit.unitType} /> : null;
}

function ChainNotes({ id, unitId, column, unitType }: { id: string; unitId: number; column: NotesUnitColumn; unitType: ChainUnitType }) {
  const { hierarchy, isLoading } = useStatisticalUnitHierarchy(id, unitType);
  if (isLoading) return null;
  return <UnitNotesBox chain={primaryChain(hierarchy, { column, id: unitId })} />;
}
