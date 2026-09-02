"use client";

import { useDrillDownData } from "@/app/reports/drilldown/use-drill-down-data";
import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { useMemo, useState } from "react";
import type { Chart } from "highcharts";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { BreadCrumb } from "@/app/reports/drilldown/bread-crumb";
import { DrillDownChart } from "@/app/reports/drilldown/drill-down-chart";
import { SearchLink } from "@/app/reports/drilldown/search-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useBaseData } from "@/atoms/base-data";
import { useTimeContext } from "@/atoms/app-derived";
import { Tables } from "@/lib/database.types";
import { Skeleton } from "@/components/ui/skeleton";
import { getUnitTypeLabel, UnitTypeTabs } from "@/app/reports/unit-type-tabs";
import { ChartExportButton } from "@/components/chart-export-button";
import {
  buildChartExportFilenameBase,
  joinSubtitleParts,
} from "@/lib/chart-export";


export default function ReportsPageClient({}) {
  const [highchartsModulesLoaded, setHighchartsModulesLoaded] = useState(false);
  const [maxStatValuesNoFiltering, setMaxStatValuesNoFiltering] = useState<
    Record<string, { region: number; activity: number }>
  >({});
  const [regionChart, setRegionChart] = useState<Chart | null>(null);
  const [activityChart, setActivityChart] = useState<Chart | null>(null);
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
  const { selectedTimeContext } = useTimeContext();

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

  const selectedYear = selectedTimeContext?.valid_on
    ? new Date(selectedTimeContext.valid_on).getFullYear()
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

  const statisticalVariables = useMemo(() => {
    return [
      {
        value: "count",
        label: "Count",
        title: `Number of ${unitTypeLabel}`,
      },
      ...(statDefinitions.map(
        ({ code, name }: Tables<"stat_definition_enabled">) => ({
          value: code!,
          label: name!,
          title: name!,
        })
      ) ?? []),
    ];
  }, [statDefinitions, unitTypeLabel]);

  // Calculate max values only for unfiltered top-level data
  useGuardedEffect(
    () => {
      if (drillDown && !region && !activityCategory) {
        setMaxStatValuesNoFiltering((prevMaxValues) => {
          const newMaxValues = { ...prevMaxValues };

          statisticalVariables.forEach(({ value }) => {
            const regionMax = Math.max(
              0,
              ...(drillDown.available.region?.map((point) =>
                value === "count"
                  ? point.count
                  : (() => {
                      const m = point.stats_summary?.[value];
                      return m && "sum" in m ? (m.sum as number) : 0;
                    })()
              ) || [])
            );
            const categoryMax = Math.max(
              0,
              ...(drillDown.available.activity_category?.map((point) =>
                value === "count"
                  ? point.count
                  : (() => {
                      const m = point.stats_summary?.[value];
                      return m && "sum" in m ? (m.sum as number) : 0;
                    })()
              ) || [])
            );

            // Initialize if not exists
            if (!newMaxValues[value]) {
              newMaxValues[value] = { region: 0, activity: 0 };
            }

            // Update only if new values are larger
            newMaxValues[value] = {
              region: Math.max(newMaxValues[value].region, regionMax),
              activity: Math.max(newMaxValues[value].activity, categoryMax),
            };
          });

          return newMaxValues;
        });
      }
    },
    [drillDown, region, activityCategory, statisticalVariables],
    "ReportsPageClient:calculateMaxValues"
  );

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col px-2">
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
        <Tabs defaultValue="count" className="p-2">
          <TabsList className="flex gap-1 w-fit rounded-full">
            {statisticalVariables.map((option) => (
              <TabsTrigger
                key={option.value}
                value={option.value}
                className="capitalize rounded-full data-[state=active]:bg-zinc-800 data-[state=active]:text-zinc-50 data-[state=active]:shadow-sm hover:text-zinc-800"
              >
                {option.label}
              </TabsTrigger>
            ))}
          </TabsList>
          {statisticalVariables.map((statisticalVariable) => (
            <TabsContent
              key={statisticalVariable.value}
              value={statisticalVariable.value}
              className="space-y-8"
            >
              <div className="space-y-6 bg-gray-50 p-4">
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
                      </div>

                      <ChartExportButton
                        chart={regionChart}
                        title={statisticalVariable.title}
                        subtitle={filterSubtitle}
                        hasActiveFilter={hasActiveDrilldownFilter}
                        filenameBase={buildChartExportFilenameBase(
                          "drilldown_by_region",
                          selectedUnitType,
                          selectedYear
                        )}
                      />
                    </div>
                    {highchartsModulesLoaded ? (
                      <DrillDownChart
                        points={drillDown.available.region}
                        onSelect={setRegion}
                        variable={statisticalVariable.value}
                        title={statisticalVariable.title}
                        maxTopLevelValue={
                          maxStatValuesNoFiltering[statisticalVariable.value]
                            ?.region
                        }
                        categoryHeader="Region"
                        onChartReady={setRegionChart}
                      />
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
                      </div>

                      <ChartExportButton
                        chart={activityChart}
                        title={statisticalVariable.title}
                        subtitle={filterSubtitle}
                        hasActiveFilter={hasActiveDrilldownFilter}
                        filenameBase={buildChartExportFilenameBase(
                          "drilldown_by_activity",
                          selectedUnitType,
                          selectedYear
                        )}
                      />
                    </div>
                    {highchartsModulesLoaded ? (
                      <DrillDownChart
                        points={drillDown.available.activity_category}
                        onSelect={setActivityCategory}
                        variable={statisticalVariable.value}
                        title={statisticalVariable.title}
                        maxTopLevelValue={
                          maxStatValuesNoFiltering[statisticalVariable.value]
                            ?.activity
                        }
                        categoryHeader="Activity Category"
                        onChartReady={setActivityChart}
                      />
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
            </TabsContent>
          ))}
          <div className="flex justify-end space-y-6 bg-gray-100 p-6 mt-4">
            <SearchLink
              region={region}
              activityCategory={activityCategory}
              unitType={selectedUnitType}
            />
          </div>
        </Tabs>
      </div>
    </div>
  );
}
