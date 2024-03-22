"use client";
import { chart } from "highcharts";
import { useEffect, useRef } from "react";

export const HistoricalReportChart = () => {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (ref.current) {
      chart({
        chart: {
          renderTo: ref.current,
        },
        series: [
          {
            type: "bar",
            id: "2014",
            name: "Establishments in 2014",
            data: [120, 130, 125, 135, 140, 145, 150, 155, 160, 165, 170, 175],
          },
        ],
      });
    }
  });

  return <div ref={ref} />;
};
