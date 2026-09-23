"use client";

import { useRef, useState } from "react";
import * as highcharts from "highcharts";
import { chart, type Chart } from "highcharts";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { ChartExportButton } from "@/components/chart-export-button";
import { buildChartExportFilenameBase, joinSubtitleParts } from "@/lib/chart-export";
import { getUnitTypeLabel } from "@/app/reports/unit-type-tabs";

export const UnitCountChart = ({
  history,
  isYearlyView,
  onYearSelect,
  unitType,
  year,
  title = "Units over time",
}: {
  readonly history: StatisticalHistoryHighcharts;
  readonly isYearlyView?: boolean;
  readonly onYearSelect?: (year: number) => void;
  readonly unitType: UnitType;
  readonly year: string;
  readonly title?: string;
}) => {
  const _ref = useRef<HTMLDivElement>(null);
  const [liveChart, setLiveChart] = useState<Chart | null>(null);

  useGuardedEffect(
    () => {
      const chartSeries = history.series;
      if (!_ref.current || !highcharts || !chartSeries) return;

      const chartInstance = chart({
        lang: {
          thousandsSep: " ",
        },
        chart: {
          type: "column",
          renderTo: _ref.current,
          backgroundColor: "white",
        },
        exporting: {
          buttons: {
            contextButton: {
              enabled: false,
            },
          },
        },
        title: {
          text: "",
        },
        xAxis: {
          type: "datetime",
        },
        yAxis: {
          title: {
            text: "Number of units",
          },
        },
        tooltip: {
          xDateFormat: isYearlyView ? "%Y" : "%Y-%m",
          shared: true,
        },
        plotOptions: {
          column: {
            borderWidth: 0,
            point: {
              events: {
                click: function () {
                  if (isYearlyView && onYearSelect) {
                    const year = new Date(this.x).getFullYear();
                    onYearSelect(year);
                  }
                },
              },
            },
          },
        },
        series: chartSeries.map((s) => ({
          type: "column",
          name: s.name,
          data: s.data,
          color: "#86ABD4",
        })),
        credits: { enabled: false },
        legend: {
          enabled: true,
        },
      });

      setLiveChart(chartInstance);

      return () => {
        setLiveChart(null);
        chartInstance.destroy();
      };
    },
    [history, isYearlyView, onYearSelect],
    "UnitsCountChart:createChart"
  );

  const filterSubtitle = joinSubtitleParts([
    getUnitTypeLabel(unitType) ?? "Units",
    year === "all" ? "All years" : `Year: ${year}`,
  ]);

  return (
    <div>
      <div className="flex justify-end mb-2">
        <ChartExportButton
          chart={liveChart}
          title={title}
          subtitle={filterSubtitle}
          filenameBase={buildChartExportFilenameBase("unitcount",unitType, year)}
        />
      </div>
      <div ref={_ref} />
    </div>
  );
};
