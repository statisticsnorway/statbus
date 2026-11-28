"use client";

import { useDrillDownData } from "@/app/reports/drilldown/use-drill-down-data";
import { useMemo, useState } from "react";
import type { Chart } from "highcharts";
import { ChartBarBig, Map as MapIcon } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { BreadCrumb } from "@/app/reports/drilldown/bread-crumb";
import { DrillDownChart } from "@/app/reports/drilldown/drill-down-chart";
import { SearchLink } from "@/app/reports/drilldown/search-link";
import { MeasurePicker } from "@/app/reports/drilldown/measure-picker";
import { RegionMap } from "@/app/reports/drilldown/region-map";
import { valueOf, type Measure } from "@/app/reports/drilldown/measures";
import { useBaseData } from "@/atoms/base-data";
import { useTimeFrame } from "@/atoms/app-derived";
import { Skeleton } from "@/components/ui/skeleton";
import { getUnitTypeLabel, UnitTypeTabs } from "@/app/reports/unit-type-tabs";
import { ChartExportButton } from "@/components/chart-export-button";
import {
  buildChartExportFilenameBase,
  joinSubtitleParts,
} from "@/lib/chart-export";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import type { DrillDownPoint } from "@/app/reports/types/drill-down";
import { WithinNote } from "@/app/reports/drilldown/within-note";

/** How the region panel draws its regions: as bars, or as circles on a map beside their table. */
type RegionView = "bars" | "map";

export default function ReportsPageClient({}) {
  const [highchartsModulesLoaded, setHighchartsModulesLoaded] = useState(false);
  const [maxStatValuesNoFiltering, setMaxStatValuesNoFiltering] = useState<
    Record<string, { region: number; activity: number }>
  >({});
  const [regionChart, setRegionChart] = useState<Chart | null>(null);
  const [activityChart, setActivityChart] = useState<Chart | null>(null);
  const [scaleRegionToSelection, setScaleRegionToSelection] = useState(false);
  const [scaleActivityToSelection, setScaleActivityToSelection] =
    useState(false);
  // The region panel's view (ppvxg2, owner 2026-11-28 14:02): the map is the flip side of the
  // region bars, as the search map is of the search list and the Regions map of the regions list.
  const [regionView, setRegionView] = useState<RegionView>("bars");
  // The measures shown, "count" and variable codes, and the primary one the bars and circles show
  // (ppvxg2, owner 2026-11-28 14:06: several measures, as the map prototype had).
  const [primaryKey, setPrimaryKey] = useState("count");
  const [shownKeys, setShownKeys] = useState<string[]>(["count"]);
  const {
    drillDown,
    isLoading,
    selectedUnitType,
    setSelectedUnitType,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  } = useDrillDownData();

  const { statDefinitions } = useBaseData();
  const { selectedTimeFrame } = useTimeFrame();

  useGuardedEffect(
    () => {
      // Pinpoint: The intermittent "hoverPoint" error in Highcharts is a classic
      // race condition. It occurs if a chart is created *before* all its required
      // modules (like 'drilldown') have finished loading. The chart instance ends
      // up in an incomplete or unstable state.
      // The fix is to ensure the modules are fully loaded before we attempt to
      // render any chart components. We use a state flag (`highchartsModulesLoaded`)
      // that is set to true only after the dynamic imports have resolved. The JSX
      // then uses this flag to conditionally render the charts or a skeleton.
      Promise.all([
        import("highcharts/modules/drilldown"),
        import("highcharts/modules/accessibility"),
        // export-data extends Exporting, so it must load after exporting resolves.
        import("highcharts/modules/exporting").then(
          () => import("highcharts/modules/export-data")
        ),
      ]).then(() => {
        setHighchartsModulesLoaded(true);
      });
    },
    [],
    "ReportsPageClient:importHighchartsModules"
  );

  const unitTypeLabel = useMemo(
    () => getUnitTypeLabel(selectedUnitType) ?? "Units",
    [selectedUnitType]
  );

  const selectedYear = selectedTimeFrame?.valid_on
    ? new Date(selectedTimeFrame.valid_on).getFullYear()
    : null;

  const formatBreadcrumbTrail = (
    points: DrillDownPoint[] | null | undefined
  ) =>
    points && points.length > 0
      ? points.map((point) => `${point.path} - ${point.name}`).join(" > ")
      : null;

  const regionTrail = formatBreadcrumbTrail(drillDown?.breadcrumb.region);

  const baseSubtitleLine = joinSubtitleParts([
    unitTypeLabel,
    selectedYear !== null ? `Year: ${selectedYear}` : null,
  ]);

  // Region/activity each get their own line once either is active — a long
  // trail crammed onto one " · "-joined line is hard to read. With no active
  // filter there's nothing to break out, so it stays a single line.
  const hasActiveDrilldownFilter =
    Boolean(regionTrail) || Boolean(activityCategory);

  const filterSubtitle = hasActiveDrilldownFilter
    ? [
        baseSubtitleLine,
        `<b>Region:</b> ${regionTrail ?? "All"}`,
        `<b>Activity:</b> ${
          activityCategory
            ? `${activityCategory.path} - ${activityCategory.name}`
            : "All"
        }`,
      ].join("<br/>")
    : baseSubtitleLine;

  // Every measure the page can show: the number of units, then the variables that add up over
  // units (int and float).
  const allMeasures = useMemo<Measure[]>(
    () => [
      { key: "count", label: unitTypeLabel },
      ...statDefinitions
        .filter((d) => d.code && (d.type === "int" || d.type === "float"))
        .map((d) => ({ key: d.code!, label: d.name ?? d.code! })),
    ],
    [statDefinitions, unitTypeLabel]
  );
  // The shown measures, the primary first, then the others in the order they were added.
  const measures = useMemo<Measure[]>(() => {
    const byKey = new Map(allMeasures.map((m) => [m.key, m]));
    const primary = byKey.get(primaryKey) ?? allMeasures[0];
    const others = shownKeys.filter((k) => k !== primary.key).flatMap((k) => byKey.get(k) ?? []);
    return [primary, ...others];
  }, [allMeasures, primaryKey, shownKeys]);
  const primary = measures[0];
  // The bars' axis title says what a bar measures.
  const primaryTitle = primary.key === "count" ? `Number of ${unitTypeLabel}` : primary.label;

  // Calculate max values only for unfiltered top-level data
  useGuardedEffect(
    () => {
      if (
        drillDown &&
        drillDown.unit_type === selectedUnitType &&
        !region &&
        !activityCategory
      ) {
        setMaxStatValuesNoFiltering((prevMaxValues) => {
          const newMaxValues = { ...prevMaxValues };
          allMeasures.forEach(({ key }) => {
            const regionMax = Math.max(
              0,
              ...(drillDown.available.region?.map((point) => valueOf(point, key)) || [])
            );
            const categoryMax = Math.max(
              0,
              ...(drillDown.available.activity_category?.map((point) => valueOf(point, key)) || [])
            );
            newMaxValues[`${selectedUnitType}::${key}`] = { region: regionMax, activity: categoryMax };
          });
          return newMaxValues;
        });
      }
    },
    [drillDown, region, activityCategory, allMeasures, selectedUnitType],
    "ReportsPageClient:calculateMaxValues"
  );

  return (
    // One width for bars and map, so switching views keeps every control in its place (owner
    // 2026-11-28 14:24: the page resized and the switch moved).
    <div className="mx-auto flex w-full max-w-screen-2xl flex-col px-2">
      <h1 className="mb-3 text-center text-2xl">Statbus Data Drilldown</h1>
      <p className="mb-4 text-center text-gray-600">
        Gain data insights by drilling through the bar charts below
      </p>
      <div className="w-full space-y-1">
        <div className="flex flex-col p-2">
          <UnitTypeTabs
            value={selectedUnitType}
            onValueChange={setSelectedUnitType}
          />
        </div>
        <div className="space-y-8 p-2">
          <MeasurePicker
            measures={allMeasures}
            selected={shownKeys}
            primary={primary.key}
            onSelected={setShownKeys}
            onPrimary={setPrimaryKey}
          />
          <div className="space-y-6 bg-gray-50 p-4" data-drilldown-region-panel="">
            {drillDown ? (
              <>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <BreadCrumb
                      topLevelText="All Regions"
                      points={drillDown.breadcrumb.region}
                      selected={region}
                      onSelect={setRegion}
                    />
                    <WithinNote kind="activity" point={activityCategory} onClear={() => setActivityCategory(null)} />
                  </div>
                  <div className="flex shrink-0 items-center gap-3">
                    {regionView === "bars" && hasActiveDrilldownFilter && (
                      <div className="flex items-center gap-1.5">
                        <Label
                          htmlFor="scale-region-to-selection"
                          className="text-xs text-gray-500"
                        >
                          Scale to selection
                        </Label>
                        <Switch
                          id="scale-region-to-selection"
                          checked={scaleRegionToSelection}
                          onCheckedChange={setScaleRegionToSelection}
                        />
                      </div>
                    )}
                    {/* Bars or map: two views of the same regions and figures. */}
                    <div
                      className="flex rounded-md border bg-white p-0.5"
                      role="group"
                      aria-label="Show the regions as"
                      data-drilldown-region-view=""
                    >
                      {(
                        [
                          { view: "bars", label: "Bars", Icon: ChartBarBig },
                          { view: "map", label: "Map", Icon: MapIcon },
                        ] as const
                      ).map(({ view, label, Icon }) => (
                        <button
                          key={view}
                          type="button"
                          aria-pressed={regionView === view}
                          className={`flex items-center gap-1 rounded px-2 py-1 text-xs font-medium ${
                            regionView === view ? "bg-gray-900 text-white" : "text-gray-600 hover:bg-gray-100"
                          }`}
                          onClick={() => setRegionView(view)}
                          data-drilldown-region-view-option={view}
                        >
                          <Icon className="h-3.5 w-3.5" />
                          {label}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
                {regionView === "map" ? (
                  <RegionMap
                    points={drillDown.available.region}
                    selection={drillDown.stats}
                    trail={drillDown.breadcrumb.region}
                    region={region}
                    onSelect={setRegion}
                    measures={measures}
                    unitType={selectedUnitType}
                    unitsLabel={unitTypeLabel}
                    activityCategory={activityCategory}
                    validOn={selectedTimeFrame?.valid_on ?? null}
                    frameName={selectedTimeFrame?.name ?? null}
                    isLoading={isLoading}
                  />
                ) : highchartsModulesLoaded ? (
                  <>
                    <DrillDownChart
                      points={drillDown.available.region}
                      onSelect={setRegion}
                      variable={primary.key}
                      title={primaryTitle}
                      maxTopLevelValue={
                        scaleRegionToSelection
                          ? undefined
                          : maxStatValuesNoFiltering[
                              `${selectedUnitType}::${primary.key}`
                            ]?.region
                      }
                      categoryHeader="Region"
                      onChartReady={setRegionChart}
                    />
                    {/* Below the chart, at the left: apart from the view switch and the scale
                        switch above (owner 2026-11-28 14:24). */}
                    <ChartExportButton
                      chart={regionChart}
                      title={primaryTitle}
                      subtitle={filterSubtitle}
                      hasActiveFilter={hasActiveDrilldownFilter}
                      filenameBase={buildChartExportFilenameBase(
                        "drilldown_by_region",
                        selectedUnitType,
                        selectedYear
                      )}
                    />
                  </>
                ) : (
                  <Skeleton className="w-full h-[200px]" />
                )}
              </>
            ) : isLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-5 w-32" />
                <Skeleton className="w-full h-[200px]" />
              </div>
            ) : null}
          </div>
          <div className="bg-gray-50 p-6">
            {drillDown ? (
              <>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <BreadCrumb
                      topLevelText="All Activity Categories"
                      points={drillDown.breadcrumb.activity_category}
                      selected={activityCategory}
                      onSelect={setActivityCategory}
                    />
                    <WithinNote kind="region" point={region} onClear={() => setRegion(null)} />
                  </div>
                  <div className="flex shrink-0 items-center gap-3">
                    {hasActiveDrilldownFilter && (
                      <div className="flex items-center gap-1.5">
                        <Label
                          htmlFor="scale-activity-to-selection"
                          className="text-xs text-gray-500"
                        >
                          Scale to selection
                        </Label>
                        <Switch
                          id="scale-activity-to-selection"
                          checked={scaleActivityToSelection}
                          onCheckedChange={setScaleActivityToSelection}
                        />
                      </div>
                    )}
                  </div>
                </div>
                {highchartsModulesLoaded ? (
                  <>
                    <DrillDownChart
                      points={drillDown.available.activity_category}
                      onSelect={setActivityCategory}
                      variable={primary.key}
                      title={primaryTitle}
                      maxTopLevelValue={
                        scaleActivityToSelection
                          ? undefined
                          : maxStatValuesNoFiltering[
                              `${selectedUnitType}::${primary.key}`
                            ]?.activity
                      }
                      categoryHeader="Activity Category"
                      onChartReady={setActivityChart}
                    />
                    <ChartExportButton
                      chart={activityChart}
                      title={primaryTitle}
                      subtitle={filterSubtitle}
                      hasActiveFilter={hasActiveDrilldownFilter}
                      filenameBase={buildChartExportFilenameBase(
                        "drilldown_by_activity",
                        selectedUnitType,
                        selectedYear
                      )}
                    />
                  </>
                ) : (
                  <Skeleton className="w-full h-[200px]" />
                )}
              </>
            ) : isLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-5 w-48" />
                <Skeleton className="w-full h-[200px]" />
              </div>
            ) : null}
          </div>
          <div className="flex justify-end space-y-6 bg-gray-100 p-6 mt-4">
            <SearchLink
              region={region}
              activityCategory={activityCategory}
              unitType={selectedUnitType}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
