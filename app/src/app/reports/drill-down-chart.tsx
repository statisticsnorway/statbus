import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { useEffect, useRef } from "react";
import type { Chart } from "highcharts";
import { chart } from "highcharts";

const ROW_HEIGHT = 40;
const BASE_HEIGHT = 50;

interface DrillDownChartProps {
  readonly points: DrillDownPoint[];
  readonly variable: string;
  readonly title: string;
  readonly onSelect: (p: DrillDownPoint) => void;
  readonly maxTopLevelValue: number;
}

export const DrillDownChart = ({
  points,
  variable,
  title,
  onSelect,
  maxTopLevelValue,
}: DrillDownChartProps) => {
  const _ref = useRef<HTMLDivElement>(null);
  const _chart = useRef<Chart | null>(null);

  useEffect(() => {
    if (_ref.current) {
      _chart.current?.destroy();
      _chart.current = chart({
        chart: {
          height: BASE_HEIGHT + ROW_HEIGHT * (points?.length ?? 0),
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
              style: {
                fontWeight: "normal",
                format: "{point.y:,.0f}",
                textOutline: "none",
              },
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
          max: maxTopLevelValue,
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
            textDecoration: "none",
          },
          activeDataLabelStyle: {
            color: "black",
            fontWeight: "normal",
            textDecoration: "none",
          },
        },
        tooltip: {
          headerFormat: "",
          pointFormat: "{point.name}: <b>\u200e{point.y}</b>",
          outside: true,
          useHTML: true,
        },
        series: [
          {
            type: "bar",
            showInLegend: false,
            data: points
              ?.filter((point) => getStatValue(point, variable) !== 0)
              .map((point) => toPointOptionObject(point, variable)),
            groupPadding: 0.05,
            minPointLength: 3,
          },
        ],
      });
    }
  }, [points, onSelect, variable, title, maxTopLevelValue]);

  return <div ref={_ref} />;
};

const getStatValue = (point: DrillDownPoint, variable: string): number =>
  variable === "count"
    ? point.count
    : ((point.stats_summary?.[variable]?.sum as number) ?? 0);

const toPointOptionObject = (point: DrillDownPoint, variable: string) => ({
  name: `${point.path} - ${point.name}`,
  y: getStatValue(point, variable),
  drilldown: point.has_children ? "1" : "",
  custom: point,
  color: "#86ABD4",
});
