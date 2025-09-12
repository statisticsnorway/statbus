import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { useRef } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
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
  const chartContainerRef = useRef<HTMLDivElement>(null);

  useGuardedEffect(() => {
    // Pinpoint: This error occurs when Highcharts event listeners (like for clicks)
    // remain attached to the DOM after the chart instance has been destroyed. This
    // typically happens during component unmounting or re-rendering if the cleanup
    // is not perfectly synchronized.

    // The fix is to ensure each chart instance is self-contained within a single
    // effect's lifecycle. We create the chart and return a cleanup function that
    // closes over *that specific chart instance*. This avoids race conditions
    // with mutable refs that can occur during fast re-renders or navigation.

    if (!chartContainerRef.current) {
      return;
    }

    const chartInstance = chart({
      chart: {
        height: BASE_HEIGHT + ROW_HEIGHT * (points?.length ?? 0),
        renderTo: chartContainerRef.current,
        events: {
          drilldown: (e) => onSelect(e.point.options.custom as DrillDownPoint),
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

    // This cleanup function is crucial. It's returned by the effect and will be
    // called by React just before the component unmounts or before the effect
    // re-runs. It closes over `chartInstance` ensuring we always destroy the
    // correct chart.
    return () => {
      chartInstance.destroy();
    };
  }, [points, onSelect, variable, title, maxTopLevelValue], 'DrillDownChart:createChart');

  return <div ref={chartContainerRef} />;
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
