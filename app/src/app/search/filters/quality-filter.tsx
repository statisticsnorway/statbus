"use client";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { useSearchFilters } from "@/atoms/search";
import { useCallback, useMemo } from "react";
import { QUALITY } from "@/app/search/filters/url-search-params";
import {
  parseQualityCheckParam,
  qualityCheckName,
  qualityCheckParam,
} from "@/lib/quality-checks";
import { useQualityChecks } from "@/app/dashboard/quality-checks-data";
import { QualityCheckInfo } from "@/app/dashboard/data-quality-cards";
import { SearchFilterOption } from "../search.d";

// Quality (05pe0x): narrows the list to the units one check of public.quality_check lists
// (quality=<rule>[:<stat code>]), and lets the user choose a check, switch it or clear it. The
// options are the switched-on checks, named as on the dashboard, each with its ⓘ. Always shown,
// like Unit Type: a quality check is not a column, so the column settings do not hide it.
export default function QualityFilter() {
  const { filters, updateFilters } = useSearchFilters();
  const { checks } = useQualityChecks();
  const filterValue = filters[QUALITY];
  const selected = useMemo(() => {
    const values = Array.isArray(filterValue)
      ? (filterValue as (string | null)[])
      : [];
    return values.filter((value): value is string => parseQualityCheckParam(value) !== null);
  }, [filterValue]);

  const options = useMemo<SearchFilterOption[]>(
    () =>
      (checks ?? [])
        .filter((check) => check.onDashboard || selected.includes(qualityCheckParam(check.rule, check.statCode)))
        .map((check) => ({
          label: qualityCheckName(check.rule, check.statName),
          value: qualityCheckParam(check.rule, check.statCode),
          humanReadableValue: qualityCheckName(check.rule, check.statName),
          info: <QualityCheckInfo rule={check.rule} statName={check.statName} />,
          // Every quality check lists units with a data-quality problem, so its
          // chip is orange like Region and Activity Category "Missing".
          className: "bg-orange-200",
        })),
    [checks, selected]
  );

  const toggle = useCallback(
    ({ value }: SearchFilterOption) => {
      const next =
        value !== null && parseQualityCheckParam(value) && !selected.includes(value) ? [value] : [];
      updateFilters({ ...filters, [QUALITY]: next });
    },
    [selected, filters, updateFilters]
  );

  const reset = useCallback(() => {
    updateFilters({ ...filters, [QUALITY]: [] });
  }, [filters, updateFilters]);

  return (
    <OptionsFilter
      className="p-2 h-9"
      title="Quality"
      options={options}
      selectedValues={selected}
      onReset={reset}
      onToggle={toggle}
    />
  );
}
