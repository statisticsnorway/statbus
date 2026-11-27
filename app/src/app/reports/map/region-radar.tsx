"use client";

import { useMemo, useRef, useState } from "react";
import { chart, type Chart } from "highcharts";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

/** One picked child region: its units and, per variable code, the exact sum and how many units carry it. */
export interface RadarRegion {
  path: string;
  name: string;
  units: number;
  stats: Record<string, { sum: number; count: number }>;
}

export interface RadarVariable {
  code: string;
  name: string;
}

/**
 * How each axis is measured. "share": the region's total as a share of the largest region on that
 * axis, so axes with different scales fit one web. "mean": the variable's mean per unit that
 * carries it, again as a share of the largest mean on that axis; the units axis has no mean, so it
 * is left out.
 */
type RadarMode = "share" | "mean";

interface Axis {
  key: string;
  name: string;
  /** The real value per region, shown in the tooltip; null where the region has none. */
  value: (r: RadarRegion) => number | null;
  unit: string;
}

const fmt = (x: number) => x.toLocaleString("en", { maximumFractionDigits: 2 });

/**
 * A spider-web chart that compares a few picked regions (ppvxg2, Reports → Map): one polygon per
 * region, one axis per measure. Axes are on different scales, so each axis is drawn as percent of
 * the largest region on it, and the tooltip gives the real value.
 */
export function RegionRadar({
  regions,
  variables,
  unitTypeLabel,
}: {
  readonly regions: readonly RadarRegion[];
  readonly variables: readonly RadarVariable[];
  /** The unit type in plural, e.g. "Enterprises": the first axis reads "Number of enterprises". */
  readonly unitTypeLabel: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [mode, setMode] = useState<RadarMode>("share");
  // highcharts-more registers the polar and spider series on Highcharts when imported; the chart
  // waits for it, as the drilldown page waits for its modules.
  const [moreLoaded, setMoreLoaded] = useState(false);
  useGuardedEffect(
    () => {
      let live = true;
      import("highcharts/highcharts-more").then(() => {
        if (live) setMoreLoaded(true);
      });
      return () => {
        live = false;
      };
    },
    [],
    "RegionRadar:loadMore"
  );

  const axes = useMemo<Axis[]>(() => {
    const perVariable = variables.map<Axis>((v) =>
      mode === "share"
        ? { key: v.code, name: v.name, unit: "total", value: (r) => r.stats[v.code]?.sum ?? null }
        : {
            key: v.code,
            name: v.name,
            unit: "mean per unit",
            value: (r) => {
              const s = r.stats[v.code];
              return s && s.count > 0 ? s.sum / s.count : null;
            },
          }
    );
    return mode === "share"
      ? [
          {
            key: "units",
            name: `Number of ${unitTypeLabel.toLocaleLowerCase()}`,
            unit: "units",
            value: (r) => r.units,
          },
          ...perVariable,
          // Each variable's mean beside its total, so one variable already spans a web (a radar of
          // two axes is a line) and a region of few large units stands apart from many small ones.
          ...variables.map<Axis>((v) => ({
            key: `${v.code}:mean`,
            name: `${v.name} per unit`,
            unit: "mean per unit",
            value: (r) => {
              const s = r.stats[v.code];
              return s && s.count > 0 ? s.sum / s.count : null;
            },
          })),
          ...variables.map<Axis>((v) => ({
            key: `${v.code}:coverage`,
            name: `Units reporting ${v.name.toLocaleLowerCase()}`,
            unit: "% of units",
            value: (r) => {
              const s = r.stats[v.code];
              return s && r.units > 0 ? (100 * s.count) / r.units : null;
            },
          })),
        ]
      : perVariable;
  }, [variables, mode, unitTypeLabel]);

  const series = useMemo(() => {
    const largest = axes.map((a) =>
      Math.max(0, ...regions.map((r) => a.value(r) ?? 0))
    );
    return regions.map((r) => ({
      type: "line" as const,
      name: r.name,
      pointPlacement: "on" as const,
      data: axes.map((a, i) => {
        const real = a.value(r);
        return {
          y: real === null || largest[i] === 0 ? 0 : (100 * real) / largest[i],
          custom: { real, unit: a.unit },
        };
      }),
    }));
  }, [axes, regions]);

  const chartRef = useRef<Chart | null>(null);
  useGuardedEffect(
    () => {
      if (!moreLoaded || !ref.current) return;
      chartRef.current?.destroy();
      chartRef.current = chart(ref.current, {
        chart: { polar: true, type: "line", height: 300, backgroundColor: "white" },
        title: { text: undefined },
        credits: { enabled: false },
        xAxis: {
          categories: axes.map((a) => a.name),
          tickmarkPlacement: "on",
          lineWidth: 0,
        },
        yAxis: {
          gridLineInterpolation: "polygon",
          min: 0,
          max: 100,
          tickInterval: 25,
          labels: { format: "{value}%" },
        },
        tooltip: {
          shared: true,
          formatter: function () {
            const points = this.points ?? [];
            const head = `<b>${String(this.x ?? points[0]?.category ?? "")}</b>`;
            const rows = points.map((p) => {
              const c = p.options.custom as { real: number | null; unit: string };
              const real = c.real === null ? "no value" : `${fmt(c.real)} ${c.unit}`;
              return `<span style="color:${String(p.color)}">●</span> ${p.series.name}: ${real} (${fmt(p.y ?? 0)}% of largest)`;
            });
            return [head, ...rows].join("<br/>");
          },
        },
        legend: { align: "center", verticalAlign: "bottom" },
        series,
      });
    },
    [moreLoaded, axes, series],
    "RegionRadar:draw"
  );
  useGuardedEffect(
    () => () => {
      chartRef.current?.destroy();
      chartRef.current = null;
    },
    [],
    "RegionRadar:destroy"
  );

  return (
    <div className="flex flex-col gap-2" data-region-radar="">
      <div className="flex items-center gap-2 text-sm" role="radiogroup" aria-label="Radar measure">
        {(
          [
            ["share", "Share of largest"],
            ["mean", "Per unit (mean)"],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={mode === value}
            className={`rounded border px-2 py-1 ${mode === value ? "bg-gray-200 font-medium" : "bg-white"}`}
            onClick={() => setMode(value)}
          >
            {label}
          </button>
        ))}
      </div>
      {mode === "mean" && variables.length === 0 ? (
        <p className="text-sm text-gray-600">Tick a variable to compare its mean per unit.</p>
      ) : regions.length === 0 ? (
        <p className="text-sm text-gray-600">Pick regions to compare.</p>
      ) : null}
      <div ref={ref} className={regions.length === 0 ? "hidden" : ""} />
    </div>
  );
}
