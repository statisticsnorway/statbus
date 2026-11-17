"use client";

import Link from "next/link";
import { useParams, usePathname } from "next/navigation";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";

/**
 * The unit whose page the edit is on, as a primary unit (owner 2026-11-17):
 * a primary legal unit gives its enterprise its name, activities, locations,
 * contact, classifications and figures, and a primary establishment does the
 * same for its legal unit or enterprise. Null when the page's unit is not
 * primary, so editing it changes only itself.
 */
export function usePrimaryUnitRole(): { parentLabel: string; parentName: string; parentHref: string } | null {
  const params = useParams();
  const pathname = usePathname();
  const id = (params?.id as string | undefined) ?? "";
  const unitType = pathname?.startsWith("/legal-units/")
    ? "legal_unit"
    : pathname?.startsWith("/establishments/")
      ? "establishment"
      : null;
  const { hierarchy } = useStatisticalUnitHierarchy(id, unitType ?? "legal_unit");
  if (!unitType || !hierarchy?.enterprise) return null;
  const unitId = parseInt(id, 10);
  const enterprise = hierarchy.enterprise;
  if (unitType === "legal_unit") {
    const lu = enterprise.legal_unit?.find((l) => l.id === unitId);
    return lu?.primary_for_enterprise
      ? { parentLabel: "enterprise", parentName: lu.name, parentHref: `/enterprises/${lu.enterprise_id}` }
      : null;
  }
  const owner = enterprise.legal_unit?.find((l) => l.establishment?.some((e) => e.id === unitId));
  const est =
    enterprise.establishment?.find((e) => e.id === unitId) ??
    owner?.establishment.find((e) => e.id === unitId);
  if (!est) return null;
  if (est.primary_for_enterprise)
    return { parentLabel: "enterprise", parentName: est.name, parentHref: `/enterprises/${est.enterprise_id}` };
  if (est.primary_for_legal_unit && owner)
    return { parentLabel: "legal unit", parentName: owner.name, parentHref: `/legal-units/${owner.id}` };
  return null;
}

/**
 * Beside Cancel and Save while editing a primary unit: the change also
 * changes the unit it is primary for. Shown where the change is made, and
 * only there (owner 2026-11-17, physical locality).
 */
export function PrimaryUnitNotice() {
  const role = usePrimaryUnitRole();
  if (!role) return null;
  return (
    <p className="mr-auto rounded bg-amber-50 px-2 py-1 text-sm text-amber-900" data-primary-unit-notice="">
      Primary for the {role.parentLabel}{" "}
      <Link className="underline" href={role.parentHref}>
        {role.parentName}
      </Link>
      : this change also changes the {role.parentLabel}.
    </p>
  );
}
