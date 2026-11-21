"use client";
import Link from "next/link";
import { useStatisticalUnitHierarchy } from "@/components/statistical-unit-details/use-unit-details";
import { useParams } from "next/navigation";
import { describeError } from "@/lib/error-format";

/**
 * Which unit the enterprise's information comes from, in a small box of its
 * own above the menu's Identification (64ae2w, owner 2026-11-21), grey so it
 * does not read as a yellow note. The enterprise's layout places this slot
 * above the menu.
 */
export default function PrimaryUnitInfo() {
  const params = useParams();
  const id = params.id as string;
  const { hierarchy, error } = useStatisticalUnitHierarchy(id, "enterprise");
  if (error) {
    throw new Error(describeError(error), { cause: error });
  }
  const primaryLegalUnit = hierarchy?.enterprise?.legal_unit?.find((lu) => lu.primary_for_enterprise);
  const primaryEstablishment = hierarchy?.enterprise?.establishment?.find((es) => es.primary_for_enterprise);
  const primaryUnit = primaryLegalUnit ?? primaryEstablishment;
  if (!primaryUnit) return null;
  return (
    <div className="mb-3 rounded-sm border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-600" data-derived-from="">
      Derived from the primary {primaryLegalUnit ? "legal unit" : "establishment"}
      <Link
        className="block truncate text-sm font-medium text-gray-900 underline underline-offset-2"
        href={`/${primaryLegalUnit ? "legal-units" : "establishments"}/${primaryUnit.id}`}
      >
        {primaryUnit.name}
      </Link>
    </div>
  );
}
