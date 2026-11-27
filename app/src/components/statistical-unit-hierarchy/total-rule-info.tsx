"use client";
import Link from "next/link";
import { Info } from "lucide-react";
import { useState, type MouseEvent } from "react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { usePermission } from "@/atoms/auth";
import { STATISTICAL_VARIABLE_COUNTING_DOC_URL } from "@/components/statistical-variable-counting";
import type { Enums } from "@/lib/database.types";

/** The unit whose Σ is explained: how its total of a variable is made depends on its type. */
export type TotalUnitType = "legal_unit" | "enterprise" | "power_group";

/**
 * The ⓘ after every Σ in the Links tree (s465ff): how that unit's total of one variable is made, in
 * the words its formula uses. A legal unit follows its variable's rule (stat_definition.lu_es_rollup):
 * sum adds its own value and its establishments' sum, max takes the larger. An enterprise sums its
 * legal units' totals and a power group its enterprises' totals, for every variable. The tree's
 * cards are links, so the click opens the explanation and goes no further.
 */
export function TotalRuleInfo({
  unitType,
  variableName,
  rule,
}: {
  readonly unitType: TotalUnitType;
  readonly variableName: string;
  readonly rule: Enums<"lu_es_rollup"> | null;
}) {
  const { canAccessAdminTools } = usePermission();
  const [open, setOpen] = useState(false);
  const toggle = (e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setOpen((o) => !o);
  };
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          onClick={toggle}
          aria-label={`How this ${variableName} total is made`}
          className="self-center rounded text-gray-400 hover:text-gray-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400"
        >
          <Info className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 space-y-2 text-sm text-gray-700" onClick={(e) => e.stopPropagation()}>
        <TotalRuleText unitType={unitType} variableName={variableName} rule={rule} />
        {unitType === "legal_unit" && (
          <p>
            Each variable sets its rule as Legal unit total, sum or max, in{" "}
            {canAccessAdminTools ? (
              <Link href="/admin/statistical-variables" className="underline" onClick={(e) => e.stopPropagation()}>
                Admin › Statistical variables
              </Link>
            ) : (
              "Admin › Statistical variables"
            )}
            . Changing it recalculates the totals.
          </p>
        )}
        <a
          href={STATISTICAL_VARIABLE_COUNTING_DOC_URL}
          target="_blank"
          rel="noreferrer"
          className="inline-block underline"
          onClick={(e) => e.stopPropagation()}
        >
          How statistical variables add up
        </a>
      </PopoverContent>
    </Popover>
  );
}

function TotalRuleText({
  unitType,
  variableName,
  rule,
}: {
  readonly unitType: TotalUnitType;
  readonly variableName: string;
  readonly rule: Enums<"lu_es_rollup"> | null;
}) {
  if (unitType === "enterprise") {
    return (
      <>
        <p className="font-medium text-gray-900">{variableName}: Σ = Σ legal units</p>
        <p>An enterprise&apos;s total is the sum of its legal units&apos; totals. Legal units do not overlap, so nothing is counted twice.</p>
      </>
    );
  }
  if (unitType === "power_group") {
    return (
      <>
        <p className="font-medium text-gray-900">{variableName}: Σ = Σ enterprises</p>
        <p>A power group&apos;s total is the sum of its enterprises&apos; totals.</p>
      </>
    );
  }
  if (rule === "max") {
    return (
      <>
        <p className="font-medium text-gray-900">{variableName}: Σ = max(legal unit, Σ establishments)</p>
        <p>
          max: the larger of the legal unit&apos;s own value and its establishments&apos; sum. The legal unit
          and its establishments report the same people, so they are counted once.
        </p>
      </>
    );
  }
  return (
    <>
      <p className="font-medium text-gray-900">{variableName}: Σ = legal unit + Σ establishments</p>
      <p>
        sum: the legal unit&apos;s own value plus its establishments&apos; sum. Each value is reported on one
        level only.
      </p>
    </>
  );
}
