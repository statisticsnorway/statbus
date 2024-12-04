"use client";

import { useDrillDownData } from "@/app/reports/use-drill-down-data";
import { useEffect, useMemo, useState } from "react";
import * as highcharts from "highcharts";
import HC_drilldown from "highcharts/modules/drilldown";
import HC_a11y from "highcharts/modules/accessibility";
import { BreadCrumb } from "@/app/reports/bread-crumb";
import { DrillDownChart } from "@/app/reports/drill-down-chart";
import { SearchLink } from "@/app/reports/search-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useBaseData } from "@/app/BaseDataClient";

export default function ReportsPageClient({
}) {
  const [maxStatValuesNoFiltering, setMaxStatValuesNoFiltering] = useState<Record<string, { region: number, activity: number }>>({});
  const {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  } = useDrillDownData();

  const { statDefinitions } = useBaseData();

  useEffect(() => {
    HC_a11y(highcharts);
    HC_drilldown(highcharts);
  }, []);

  const statisticalVariables = useMemo(() => {
    return [
      { value: "count", label: "Count", title: "Number of enterprises" },
      ...(statDefinitions.map(({ code, name }) => ({
        value: code!,
        label: name!,
        title: name!,
      })) ?? []),
    ];
  }, [statDefinitions]);

  // Calculate max values only for unfiltered top-level data
  useEffect(() => {
    if (drillDown && !region && !activityCategory) {
      setMaxStatValuesNoFiltering(prevMaxValues => {
        const newMaxValues = { ...prevMaxValues };

        statisticalVariables.forEach(({ value }) => {
          const regionMax = Math.max(...drillDown.available.region.map(point =>
            value === "count" ? point.count : (point.stats_summary?.[value]?.sum as number) ?? 0
          ));
          const categoryMax = Math.max(...drillDown.available.activity_category.map(point =>
            value === "count" ? point.count : (point.stats_summary?.[value]?.sum as number) ?? 0
          ));

          // Initialize if not exists
          if (!newMaxValues[value]) {
            newMaxValues[value] = { region: 0, activity: 0 };
          }

          // Update only if new values are larger
          newMaxValues[value] = {
            region: Math.max(newMaxValues[value].region, regionMax),
            activity: Math.max(newMaxValues[value].activity, categoryMax)
          };
        });

        return newMaxValues;
      });
    }
  }, [drillDown, region, activityCategory, statisticalVariables]);

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col px-2 py-8 md:py-12">
      <h1 className="mb-3 text-center text-2xl">Statbus Data Drilldown</h1>
      <p className="mb-12 text-center">
        Gain data insights by drilling through the bar charts below
      </p>
      <div className="w-full space-y-8">
        <Tabs defaultValue="count">
          <TabsList className="mx-auto">
            {statisticalVariables.map((statisticalVariable) => (
              <TabsTrigger
                key={statisticalVariable.value}
                value={statisticalVariable.value}
                className="capitalize"
              >
                {statisticalVariable.label}
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
                {drillDown && (
                  <>
                    <BreadCrumb
                      topLevelText="All Regions"
                      points={drillDown.breadcrumb.region}
                      selected={region}
                      onSelect={setRegion}
                    />
                    <DrillDownChart
                      points={drillDown.available.region}
                      onSelect={setRegion}
                      variable={statisticalVariable.value}
                      title={statisticalVariable.title}
                      maxTopLevelValue={maxStatValuesNoFiltering[statisticalVariable.value]?.region}
                    />
                  </>
                )}
              </div>
              <div className="bg-gray-50 p-6">
                {drillDown && (
                  <>
                    <BreadCrumb
                      topLevelText="All Activity Categories"
                      points={drillDown.breadcrumb.activity_category}
                      selected={activityCategory}
                      onSelect={setActivityCategory}
                    />
                    <DrillDownChart
                      points={drillDown.available.activity_category}
                      onSelect={setActivityCategory}
                      variable={statisticalVariable.value}
                      title={statisticalVariable.title}
                      maxTopLevelValue={maxStatValuesNoFiltering[statisticalVariable.value]?.activity}
                    />
                  </>
                )}
              </div>
            </TabsContent>
          ))}
        </Tabs>
        <div className="flex justify-end space-y-6 bg-gray-100 p-6">
          <SearchLink region={region} activityCategory={activityCategory} />
        </div>
      </div>
    </main>
  );
}
