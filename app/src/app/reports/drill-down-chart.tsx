import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { useEffect, useRef } from "react";
import type { Chart } from "highcharts";
import { chart } from "highcharts";

interface DrillDownChartProps {
  readonly points: DrillDownPoint[];
  readonly onSelect: (p: DrillDownPoint) => void;
}

export const DrillDownChart = ({ points, onSelect }: DrillDownChartProps) => {
  const _ref = useRef<HTMLDivElement>(null);
  const _chart = useRef<Chart | null>(null);

  useEffect(() => {
    if (_ref.current) {
      _chart.current?.destroy();
      _chart.current = chart({
        chart: {
          renderTo: _ref.current,
          events: {
            drilldown: (e) =>
              onSelect(e.point.options.custom as DrillDownPoint),
          },
          backgroundColor: "transparent",
        },
        plotOptions: {
          series: {
            borderWidth: 0,
            dataLabels: {
              enabled: true,
              format: "{point.y}",
            },
          },
        },
        title: {
          text: "",
        },
        xAxis: {
          type: "category",
        },
        yAxis: {
          visible: false,
        },
        drilldown: {
          activeAxisLabelStyle: {
            color: "black",
            fontWeight: "normal",
          },
          activeDataLabelStyle: {
            color: "black",
            fontWeight: "normal",
            textDecoration: "none",
          },
        },
        tooltip: {
          headerFormat: "",
          pointFormat: "{point.name}: <b>{point.y}</b>",
          outside: true,
          useHTML: true,
        },
        series: [
          {
            type: "bar",
            showInLegend: false,
            data: points?.map(toPointOptionObject),
            groupPadding: 0.05,
          },
        ],
      });
    }
  }, [points, onSelect]);

  return <div ref={_ref} />;
};

const toPointOptionObject = (point: DrillDownPoint) => ({
  name: point.name,
  y: point.count,
  drilldown: point.has_children ? "1" : "",
  custom: point,
  color: "#00719c",
});
