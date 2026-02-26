"use client";

import { useCallback, useMemo, useState, type ReactNode } from "react";

import { useStatisticalHistoryHighcharts } from "./history-changes/use-statistical-history-highcharts";
import { Skeleton } from "@/components/ui/skeleton";
import { useTimeContext } from "@/atoms/app-derived";
import { type Enums } from "@/lib/database.types";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import { UnitTypeTabs } from "./unit-type-tabs";


interface HistoryReportsProps {
  readonly title: string;
  readonly subtitle: string;
  readonly seriesCodes: string[];
  readonly children: (props: {
    history: StatisticalHistoryHighcharts;
    isYearlyView: boolean;
    onYearSelect: (year: number) => void;
  }) => ReactNode;
}

export function HistoryReports({
  title,
  subtitle,
  seriesCodes,
  children,
}: HistoryReportsProps) {
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

  const { history, isLoading } = useStatisticalHistoryHighcharts(
    resolution,
    selectedUnitType,
    seriesCodes,
    selectedYear !== "all" ? parseInt(selectedYear, 10) : undefined
  );

  const handleYearSelect = useCallback((year: number) => {
    setSelectedYear(year.toString());
  }, []);

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col px-2">
      <header className="mb-4 text-center">
        <h1 className="mb-3 text-2xl">{title}</h1>
        <p className="text-gray-600">{subtitle}</p>
      </header>
      <div className="w-full space-y-4">
        <div className="rounded-md p-2">
          <div className="flex justify-between">
            <UnitTypeTabs
              value={selectedUnitType}
              onValueChange={setSelectedUnitType}
            />
          
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
        </div>
        {!isLoading && history ? (
          children({
            history,
            isYearlyView: selectedYear === "all",
            onYearSelect: handleYearSelect,
          })
        ) : (
          <Skeleton className="h-[400px] " />
        )}
      </div>
    </div>
  );
}
