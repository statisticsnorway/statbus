"use client";

import { useParams, usePathname } from "next/navigation";
import { UnitNotesBox } from "./unit-notes-box";
import type { NotesUnitColumn } from "./unit-notes";

const COLUMN_BY_SEGMENT: Record<string, NotesUnitColumn> = {
  "legal-units": "legal_unit_id",
  establishments: "establishment_id",
  enterprises: "enterprise_id",
  "power-groups": "power_group_id",
};

/** The notes box for the unit whose pages these are, named by the URL (/legal-units/29/...). */
export function UnitNotesForPage() {
  const params = useParams();
  const pathname = usePathname();
  const column = COLUMN_BY_SEGMENT[pathname?.split("/")[1] ?? ""];
  const unitId = parseInt((params?.id as string | undefined) ?? "", 10);
  if (!column || !Number.isFinite(unitId)) return null;
  return <UnitNotesBox column={column} unitId={unitId} />;
}
