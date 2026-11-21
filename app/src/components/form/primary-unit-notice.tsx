"use client";

import Link from "next/link";
import { useParams, usePathname } from "next/navigation";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { editChangesEnterprise } from "./primary-unit-flow";

/**
 * The enterprise a page's unit is primary for (owner 2026-11-17): a primary
 * legal unit passes values to its enterprise, and so does the primary
 * establishment of an enterprise without legal units (doc/primary-units.md).
 * Null when the page's unit is primary for no enterprise. A legal unit's
 * primary establishment passes nothing to the legal unit, so it has no role.
 */
export function usePrimaryUnitRole(): {
  primary: "legal_unit" | "establishment";
  enterpriseHasShortName: boolean;
  parentName: string;
  parentHref: string;
} | null {
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
  const enterpriseHasShortName = !!enterprise.short_name?.trim();
  if (unitType === "legal_unit") {
    const lu = enterprise.legal_unit?.find((l) => l.id === unitId);
    return lu?.primary_for_enterprise
      ? { primary: "legal_unit", enterpriseHasShortName, parentName: lu.name, parentHref: `/enterprises/${lu.enterprise_id}` }
      : null;
  }
  const est = enterprise.establishment?.find((e) => e.id === unitId);
  return est?.primary_for_enterprise
    ? { primary: "establishment", enterpriseHasShortName, parentName: est.name, parentHref: `/enterprises/${est.enterprise_id}` }
    : null;
}

/**
 * Beside Cancel and Save while editing a field of a primary unit that its
 * enterprise takes over (ep47vn): this change also changes the enterprise.
 * Shown where the change is made, and only for fields that flow
 * (editChangesEnterprise): not for identifiers or statistics, and not for the
 * name while the enterprise has a short name of its own.
 */
export function PrimaryUnitNotice({ fieldId }: { fieldId: string }) {
  const role = usePrimaryUnitRole();
  if (!role || !editChangesEnterprise(fieldId, role.primary, role.enterpriseHasShortName)) return null;
  return (
    <p className="mr-auto rounded bg-amber-50 px-2 py-1 text-sm text-amber-900" data-primary-unit-notice="">
      Primary for the enterprise{" "}
      <Link className="underline" href={role.parentHref}>
        {role.parentName}
      </Link>
      : this change also changes the enterprise.
    </p>
  );
}
