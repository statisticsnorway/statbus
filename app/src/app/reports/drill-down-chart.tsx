import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { useEffect, useRef } from "react";
import type { Chart } from "highcharts";
import { chart } from "highcharts";

interface DrillDownChartProps {
  readonly points: DrillDownPoint[];
  readonly variable: keyof DrillDownPoint;
  readonly title: string;
  readonly onSelect: (p: DrillDownPoint) => void;
}

export const DrillDownChart = ({
  points,
  variable,
  title,
  onSelect,
}: DrillDownChartProps) => {
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
              format: "{point.y:,.0f}",
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
          visible: true,
          gridLineColor: "transparent",
          title: {
            text: title,
          },
          labels: {
            enabled: false,
          },
        },
        credits: {
          href: "",
          style: {
            cursor: "default",
          },
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
            data: points
              ?.filter((point) => point[variable] !== 0)
              .map((point) => toPointOptionObject(point, variable)),
            groupPadding: 0.05,
            minPointLength: 3,
          },
        ],
      });
    }
  }, [points, onSelect, variable]);

  return <div ref={_ref} />;
};

const toPointOptionObject = (
  point: DrillDownPoint,
  variable: keyof DrillDownPoint
) => ({
  name: `${point.path} - ${point.name}`,
  y: point[variable] as number,
  drilldown: point.has_children ? "1" : "",
  custom: point,
  color: "#00719c",
});
