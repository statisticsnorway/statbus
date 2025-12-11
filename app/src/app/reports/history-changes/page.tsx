"use client";

import React, { useState } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useStatisticalHistoryChanges } from "./use-statistical-history-changes";
import { HistoryChangesChart } from "./history-changes-chart";
import { Skeleton } from "@/components/ui/skeleton";

const unitTypes: { value: UnitType; label: string }[] = [
  { value: "enterprise", label: "Enterprises" },
  { value: "legal_unit", label: "Legal Units" },
  { value: "establishment", label: "Establishments" },
];

export default function HistoryChangesPage() {
  const [activeUnitType, setActiveUnitType] = useState<UnitType>("enterprise");
  const { history, isLoading } = useStatisticalHistoryChanges(
    activeUnitType,
    "year",
    [
      "births",
      "deaths",
      "name_change_count",
      "primary_activity_category_change_count",
      "physical_region_change_count",
    ]
  );

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col px-2 py-8 md:py-12">
      <h1 className="mb-3 text-center text-2xl">Changes over time</h1>
      <p className="mb-12 text-center">
        Annual overview of births, deaths, name changes, and other changes
      </p>
      <div className="w-full space-y-8">
        <Tabs
          defaultValue="enterprise"
          onValueChange={(value) => setActiveUnitType(value as UnitType)}
        >
          <TabsList className="mx-auto">
            {unitTypes.map((unitType) => (
              <TabsTrigger key={unitType.value} value={unitType.value}>
                {unitType.label}
              </TabsTrigger>
            ))}
          </TabsList>
          {unitTypes.map((unitType) => (
            <TabsContent
              key={unitType.value}
              value={unitType.value}
              className="space-y-8"
            >
              {!isLoading && history ? (
                <HistoryChangesChart history={history} />
              ) : (
                <Skeleton className="w-full h-[400px]" />
              )}
            </TabsContent>
          ))}
        </Tabs>
      </div>
    </main>
  );
}
