"use client";

import { useEffect } from "react";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import * as highcharts from "highcharts";
import HC_drilldown from "highcharts/modules/drilldown";
import HC_a11y from "highcharts/modules/accessibility";
import { BreadCrumb } from "@/app/reports/bread-crumb";
import { DrillDownChart } from "@/app/reports/drill-down-chart";
import { useDrillDownData } from "@/app/reports/use-drill-down-data";
import { SearchLink } from "@/app/reports/search-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export default function StatBusChart(props: { readonly drillDown: DrillDown }) {
  const {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  } = useDrillDownData(props.drillDown);

  useEffect(() => {
    HC_a11y(highcharts);
    HC_drilldown(highcharts);
  }, []);

  const statisticalVariables: {
    value: keyof DrillDownPoint;
    label: string;
    title: string;
  }[] = [
    { value: "count", label: "Count", title: "Number of enterprises" },
    { value: "employees", label: "Employees", title: "Number of employees" },
    { value: "turnover", label: "Turnover", title: "Total turnover" },
  ];

  return (
    <div className="w-full space-y-8">
      <Tabs defaultValue="count">
        <TabsList className="mx-auto">
          {statisticalVariables.map((statisticalVariable) => (
            <TabsTrigger
              key={statisticalVariable.value}
              value={statisticalVariable.value}
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
  );
}
