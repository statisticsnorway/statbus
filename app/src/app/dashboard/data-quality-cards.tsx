"use client";

import Link from "next/link";
import { Info, Settings } from "lucide-react";
import { useAtomValue } from "jotai";
import { MouseEvent, useState } from "react";
import { useTimeFrame } from "@/atoms/app-derived";
import { userRoleAtom } from "@/atoms/auth";
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { ExactCount } from "@/components/exact-count";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  QUALITY_RULE_WORDING,
  qualityCheckExplanation,
  qualityCheckHref,
  qualityCheckName,
  type QualityRule,
} from "@/lib/quality-checks";
import {
  useQualityChecks,
  useQualityFindingCounts,
  type QualityCheckRow,
} from "@/app/dashboard/quality-checks-data";

/** The ⓘ of a check: its explanation, and the guideline section for the rule when there is one. */
export function QualityCheckInfo({
  rule,
  statName,
}: {
  readonly rule: QualityRule;
  readonly statName: string | null;
}) {
  const guideHref = QUALITY_RULE_WORDING[rule].guideHref;
  const [open, setOpen] = useState(false);
  // The card is a link: the ⓘ opens its explanation and does not follow the link.
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
          className="inline-flex items-center rounded text-gray-500 hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
          aria-label={`About ${qualityCheckName(rule, statName)}`}
        >
          <Info className="h-4 w-4" />
        </button>
      </PopoverTrigger>
      <PopoverContent className="w-80 text-sm" onClick={(e) => e.stopPropagation()}>
        <p className="font-medium">{qualityCheckName(rule, statName)}</p>
        <p className="mt-2 text-gray-700">{qualityCheckExplanation(rule, statName)}</p>
        {guideHref && (
          <a href={guideHref} target="_blank" rel="noreferrer" className="mt-2 inline-block text-blue-600 underline">
            How variables add up between legal units and establishments
          </a>
        )}
      </PopoverContent>
    </Popover>
  );
}

function QualityCheckCard({
  check,
  count,
  failed,
}: {
  readonly check: QualityCheckRow;
  readonly count: number | null;
  readonly failed: boolean;
}) {
  return (
    <Link href={qualityCheckHref(check.rule, check.statCode)}>
      <DashboardCard
        title={qualityCheckName(check.rule, check.statName)}
        icon={<QualityCheckInfo rule={check.rule} statName={check.statName} />}
        failed={failed || (count ?? 0) > 0}
      >
        <ExactCount count={count} failed={failed} />
      </DashboardCard>
    </Link>
  );
}

/**
 * The Data quality section's gear: for admins, a link to Admin > Data quality checks, where each
 * check is switched on or off. Shown whether or not a check is off, so the setting is always found.
 */
export function DataQualitySettingsLink() {
  const role = useAtomValue(userRoleAtom);
  if (role !== "admin_user") return null;
  return (
    <Link
      href="/admin/quality-checks"
      className="rounded text-gray-500 hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
      aria-label="Choose which data quality checks to show"
      title="Choose which data quality checks to show"
    >
      <Settings className="h-4 w-4" />
    </Link>
  );
}

/**
 * The dashboard's Data quality cards: one per switched-on check in use of public.quality_check, in
 * its order, each counting the units the check lists at the selected time frame from one request
 * (useQualityFindingCounts, rpc/quality_check_count). Admins choose which checks show with the section's gear
 * (DataQualitySettingsLink, Admin > Data quality checks).
 */
export function DataQualityCards() {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on ?? null;
  const { checks, error } = useQualityChecks();
  const { counts, failed } = useQualityFindingCounts(validOn);

  if (error) {
    return <p className="col-span-full text-sm text-orange-700">The data quality checks could not be read.</p>;
  }
  if (!checks) {
    return <p className="col-span-full text-sm text-gray-500">Reading the data quality checks…</p>;
  }
  const shown = checks.filter((c) => c.onDashboard);
  return (
    <>
      {shown.map((check) => (
        <QualityCheckCard
          key={check.id}
          check={check}
          count={counts ? counts.get(check.id) ?? 0 : null}
          failed={failed}
        />
      ))}
    </>
  );
}
