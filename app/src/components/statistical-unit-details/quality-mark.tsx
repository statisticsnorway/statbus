"use client";
import { TriangleAlert } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { qualityCheckExplanation, qualityCheckName } from "@/lib/quality-checks";
import type { UnitQualityFinding } from "@/lib/quality-marks";

/**
 * The mark beside a field that quality checks flag (b6f1pw): an amber warning that opens the
 * checks' names and explanations, in the dashboard cards' wording (QUALITY_RULE_WORDING). It shows
 * nothing when no check flags the field.
 */
export function QualityMark({ findings }: { readonly findings?: readonly UnitQualityFinding[] }) {
  if (!findings || findings.length === 0) return null;
  const names = findings.map((f) => qualityCheckName(f.rule, f.statName));
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`Quality: ${names.join("; ")}`}
          className="ml-1 inline-flex items-center rounded text-amber-600 hover:text-amber-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
          data-quality-mark={findings.map((f) => f.rule).join(" ")}
        >
          <TriangleAlert className="h-4 w-4" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 text-sm font-normal normal-case">
        {findings.map((f) => (
          <div key={f.checkId} className="[&+&]:mt-3">
            <p className="font-medium">{qualityCheckName(f.rule, f.statName)}</p>
            <p className="mt-1 text-gray-700">{qualityCheckExplanation(f.rule, f.statName)}</p>
          </div>
        ))}
      </PopoverContent>
    </Popover>
  );
}
