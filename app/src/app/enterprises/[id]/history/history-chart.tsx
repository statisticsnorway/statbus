"use client";
import { useEffect, useRef } from "react";
import * as highcharts from "highcharts";
import type { Chart } from "highcharts";
import { chart } from "highcharts";

export const HistoryChart = ({
  history,
}: {
  readonly history: StatisticalUnitHistoryHighcharts;
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
  ];

  useEffect(() => {
    const chartSeries = history.series;
    if (!_ref.current || !highcharts || chartSeries.length === 0) return;
    _chart.current?.destroy();

    // Detect if any series represents data that is current (no end date).
    const isCurrent = chartSeries.some((s) => s.is_current);

    // Optional subtitle text
    const subtitleText = isCurrent
      ? "* Indicates value with no defined end date"
      : "";

    const yAxes = chartSeries.map((s, i) => ({
      title: {
        text: s.name,
        style: {
          color: colors[i % colors.length],
        },
      },
      gridLineColor: "gray",
      gridLineWidth: 0.3,
      lineColor: colors[i % colors.length],
      lineWidth: 1,
      opposite: i % 2 === 1,
      visible: i < 2,
      labels: {
        style: {
          color: colors[i % colors.length],
        },
      },
    }));

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
        text: history.unit_name,
      },
      xAxis: {
        type: "datetime",
      },
      yAxis: yAxes,
      tooltip: {
        xDateFormat: "%Y-%m-%d",
        shared: true,
      },
      colors: colors,
      subtitle: {
        text: subtitleText,
        verticalAlign: "bottom",
        style: {
          fontSize: "10px",
          color: "#666",
        },
      },
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

      series: chartSeries.map((s, i) => ({
        type: "column",
        name: s.name,
        data: s.data,
        yAxis: i,
        visible: i < 2,
        color: colors[i % colors.length],
        events: {
          hide: function () {
            this.chart.yAxis[this.options.yAxis as number].update({
              visible: false,
            });
          },
          show: function () {
            this.chart.yAxis[this.options.yAxis as number].update({
              visible: true,
            });
          },
        },
      })),
      credits: { enabled: false },
      legend: {
        enabled: true,
      },
    });
  }, [history]);

  return <div ref={_ref} />;
};
