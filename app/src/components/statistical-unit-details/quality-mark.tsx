"use client";
import { TriangleAlert } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { qualityCheckExplanation, qualityCheckName } from "@/lib/quality-checks";
import type { UnitQualityFinding } from "@/lib/quality-marks";

/**
 * The mark beside a field that quality checks flag (b6f1pw): an amber warning followed by each
 * check's name in the chip the search's Quality filter shows for it (orange, the dashboard cards'
 * wording, QUALITY_RULE_WORDING), so the unit page and the search name a check alike. Clicking it
 * opens the checks' explanations. It shows nothing when no check flags the field.
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
          className="ml-1 inline-flex items-center gap-1 rounded text-amber-600 hover:text-amber-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
          data-quality-mark={findings.map((f) => f.rule).join(" ")}
        >
          <TriangleAlert className="h-4 w-4" />
          {names.map((name) => (
            // The search's Quality chip (quality-filter.tsx): orange, every check lists a problem.
            <Badge key={name} variant="secondary" className="rounded-sm px-2 text-[13px] font-medium normal-case text-gray-900 bg-orange-200">
              {name}
            </Badge>
          ))}
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
