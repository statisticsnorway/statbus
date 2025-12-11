"use client";
import { useRef } from "react";
import * as highcharts from "highcharts";
import type { Chart } from "highcharts";
import { chart } from "highcharts";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export const HistoryChangesChart = ({
  history,
}: {
  readonly history: StatisticalHistoryHighcharts;
}) => {
  const _ref = useRef<HTMLDivElement>(null);
  const _chart = useRef<Chart | null>(null);


  const colors = [
    "#1A3A70",
    "#4B8B3B",
    "#AA4643",
    "#80699B",
    "#D6995C",
    "#628DCB",
    "#C7B491",
    "#f45b5b",
    "#e4d354",
    "#89A54E",
    "#2b908f",
    "#CAC47F",
  ].reverse();

  useGuardedEffect(
    () => {
      const chartSeries = history.series;
      if (!_ref.current || !highcharts || !chartSeries) return;
      _chart.current?.destroy();

      _chart.current = chart({
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
            text: "Change count",
          },
        },
        tooltip: {
          xDateFormat: "%Y-%m-%d",
          shared: true,
        },
        colors: colors,
        plotOptions: {
          series: {
            connectNulls: false,
            marker: { radius: 3, enabled: true },
            states: {
              inactive: {
                opacity: 1,
              },
            },
          },
          column: {
            borderWidth: 0,
          },
        },

        series: chartSeries
          .sort((a, b) => a.priority - b.priority)
          .map((s, i) => ({
            type: "column",
            name: s.name,
            data: s.data,
            visible: i < 5,
            color: colors[i % colors.length],
          })),
        credits: { enabled: false },
        legend: {
          enabled: true,
        },
      });
    },
    [history],
    "HistoryChangesChart:createChart"
  );

  return <div ref={_ref} />;
};
