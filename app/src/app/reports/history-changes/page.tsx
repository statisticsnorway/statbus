"use client";

import { useMemo, useState } from "react";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useStatisticalHistoryChanges } from "./use-statistical-history-changes";
import { HistoryChangesChart } from "./history-changes-chart";
import { Skeleton } from "@/components/ui/skeleton";
import { useTimeContext } from "@/atoms/app-derived";
import { Enums } from "@/lib/database.types";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const unitTypes: { value: UnitType; label: string }[] = [
  { value: "enterprise", label: "Enterprises" },
  { value: "legal_unit", label: "Legal Units" },
  { value: "establishment", label: "Establishments" },
];

export default function HistoryChangesPage() {
  const { timeContexts } = useTimeContext();
  const [selectedUnitType, setSelectedUnitType] =
    useState<UnitType>("enterprise");
  const [selectedYear, setSelectedYear] = useState<string>("all");
  const resolution: Enums<"history_resolution"> =
    selectedYear === "all" ? "year" : "year-month";

  const availableYears = useMemo(() => {
    const years = timeContexts
      .map((tc) =>
        tc.valid_from ? new Date(tc.valid_from).getFullYear() : null
      )
      .filter((year): year is number => year !== null);

    return Array.from(new Set(years)).sort((a, b) => b - a);
  }, [timeContexts]);

  const { history, isLoading } = useStatisticalHistoryChanges(
    selectedUnitType,
    resolution,
    [
      "births",
      "deaths",
      "name_change_count",
      "primary_activity_category_change_count",
      "physical_region_change_count",
    ],
    selectedYear != "all" ? parseInt(selectedYear, 10) : undefined
  );

  const handleYearSelect = (year: number) => {
    setSelectedYear(year.toString());
  };


  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col px-2 py-8 md:py-12">
      <h1 className="mb-3 text-center text-2xl">Changes over time</h1>
      <p className="mb-12 text-center">
        Annual overview of births, deaths, name changes, and other changes
      </p>
      <div className="w-full space-y-8">
        <div className="flex justify-between">
          <Tabs
            value={selectedUnitType}
            onValueChange={(value) => setSelectedUnitType(value as UnitType)}
          >
            <TabsList>
              {unitTypes.map((unitType) => (
                <TabsTrigger key={unitType.value} value={unitType.value}>
                  {unitType.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <Select value={selectedYear} onValueChange={setSelectedYear}>
            <SelectTrigger className="w-[180px]">
              <SelectValue placeholder="Select Year" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Years</SelectItem>
              {availableYears.map((year) => (
                <SelectItem key={year} value={year.toString()}>
                  {year}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div>
          {!isLoading && history ? (
            <HistoryChangesChart
              history={history}
              isYearlyView={selectedYear === "all"}
              onYearSelect={handleYearSelect}
            />
          ) : (
            <Skeleton className="w-full h-[400px]" />
          )}
        </div>
      </div>
    </main>
  );
}
