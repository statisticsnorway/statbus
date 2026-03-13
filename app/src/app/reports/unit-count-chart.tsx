"use client";

import { useRef } from "react";
import * as highcharts from "highcharts";
import { chart } from "highcharts";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export const UnitCountChart = ({
  history,
  isYearlyView,
  onYearSelect,
}: {
  readonly history: StatisticalHistoryHighcharts;
  readonly isYearlyView?: boolean;
  readonly onYearSelect?: (year: number) => void;
}) => {
  const _ref = useRef<HTMLDivElement>(null);

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

      return () => {
        chartInstance.destroy();
      };
    },
    [history, isYearlyView, onYearSelect],
    "UnitsCountChart:createChart"
  );

  return <div ref={_ref} />;
};
