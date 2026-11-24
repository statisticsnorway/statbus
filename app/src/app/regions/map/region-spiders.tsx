"use client";

import { useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UNIT_TYPE_LABEL, type MapUnitType, type RegionFeatureProperties } from "@/components/map/map-data";
import { cssColour } from "@/components/map/unit-map";

/** Above this many circles in view, only the clicked region shows its legs, so the map stays readable. */
const ALL_LEGS_UP_TO = 25;
const NODE_RADIUS = 12;
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });

/** A circle's radius as the map draws it (page.tsx scaleToView): the area follows the count, the largest in view 28 px. */
function circleRadius(total: number, top: number): number {
  return 4 + (Math.sqrt(total) / Math.sqrt(Math.max(top, 1))) * 24;
}

/**
 * The type counts of each region, drawn as legs from its circle (owner 2026-11-24, z2qt08): with
 * several unit types picked a circle is grey and its number the sum, so each circle gets one
 * short leg per picked type to a node in that type's colour with its count. The legs fan over the
 * circle's top, leaving the region's name and total below readable. With up to 25 circles in view
 * every circle has its legs; with more, only the clicked one (`focus`). A click on a node opens
 * that region's preview, as a click on its circle does.
 */
export function RegionSpiders({
  map,
  features,
  unitTypes,
  focus,
  onPick,
}: {
  map: MapLibreMap;
  features: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>[];
  unitTypes: readonly MapUnitType[];
  /** The region whose preview is open: it keeps its legs when the others are left out. */
  focus: string | null;
  onPick: (feature: GeoJSON.Feature<GeoJSON.Point, RegionFeatureProperties>) => void;
}) {
  // The map's view, read again on every move so the legs follow their circles.
  const [, setTick] = useState(0);
  useGuardedEffect(
    () => {
      const redraw = () => setTick((t) => t + 1);
      map.on("move", redraw);
      map.on("resize", redraw);
      return () => {
        map.off("move", redraw);
        map.off("resize", redraw);
      };
    },
    [map],
    "RegionSpiders:follow"
  );

  if (unitTypes.length < 2) return null;
  const bounds = map.getBounds();
  const inView = features.filter((f) => bounds.contains(f.geometry.coordinates as [number, number]));
  const top = inView.reduce((m, f) => Math.max(m, f.properties.total), 1);
  const drawn = inView.length <= ALL_LEGS_UP_TO ? inView : inView.filter((f) => f.properties.path === focus);
  // The legs fan over the top: two types at 10 and 2 o'clock, three at 10, 12 and 2.
  const angles = unitTypes.map((_, i) => (-Math.PI / 2) + (unitTypes.length === 1 ? 0 : (i / (unitTypes.length - 1) - 0.5) * (2 * Math.PI) / 3));

  return (
    <svg className="pointer-events-none absolute inset-0 h-full w-full overflow-visible" aria-hidden={drawn.length === 0} data-region-spiders="">
      {drawn.map((f) => {
        const p = map.project(f.geometry.coordinates as [number, number]);
        const r = circleRadius(f.properties.total, top);
        const leg = r + NODE_RADIUS + 8;
        return (
          <g key={f.properties.path} data-region-spider={f.properties.path}>
            {unitTypes.map((t, i) => {
              const x = p.x + leg * Math.cos(angles[i]);
              const y = p.y + leg * Math.sin(angles[i]);
              const count = f.properties[t];
              const label = `${f.properties.name}: ${count.toLocaleString()} ${UNIT_TYPE_LABEL[t].toLowerCase()}`;
              return (
                <g
                  key={t}
                  className="pointer-events-auto cursor-pointer"
                  onClick={() => onPick(f)}
                  role="button"
                  aria-label={label}
                  data-region-spider-node={t}
                >
                  <title>{label}</title>
                  <line
                    x1={p.x + r * Math.cos(angles[i])}
                    y1={p.y + r * Math.sin(angles[i])}
                    x2={x - NODE_RADIUS * Math.cos(angles[i])}
                    y2={y - NODE_RADIUS * Math.sin(angles[i])}
                    stroke="#4b5563"
                    strokeWidth={1.5}
                  />
                  <circle cx={x} cy={y} r={NODE_RADIUS} fill={cssColour(`--color-${t}-500`)} stroke="#ffffff" strokeWidth={2} />
                  <text x={x} y={y} textAnchor="middle" dominantBaseline="central" fontSize={9.5} fontWeight={600} fill="#ffffff">
                    {compact.format(count)}
                  </text>
                </g>
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}
