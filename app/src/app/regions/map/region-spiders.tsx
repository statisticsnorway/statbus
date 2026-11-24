"use client";

import { useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UNIT_TYPE_LABEL, type MapUnitType, type RegionFeatureProperties } from "@/components/map/map-data";
import { cssColour } from "@/components/map/unit-map";

const NODE_RADIUS = 10;
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });

/** A count's pill: wide enough for its digits at the 10 px bold font, never narrower than round. */
function pillWidth(text: string): number {
  return Math.max(2 * NODE_RADIUS, 8 + text.length * 6.2);
}

/** A circle's radius as the map draws it (page.tsx scaleToView): the area follows the count, the largest in view 28 px. */
function circleRadius(total: number, top: number): number {
  return 4 + (Math.sqrt(total) / Math.sqrt(Math.max(top, 1))) * 24;
}

/**
 * The type counts of each region, drawn as legs from its circle (owner 2026-11-24, z2qt08): with
 * several unit types picked a circle is grey and its number the sum, so each circle gets one
 * short leg per picked type to a pill in that type's colour with its count, the pills in a column
 * to the circle's right. Every circle in view can have its pills (owner 2026-11-24: Trøndelag's 38
 * municipalities showed none under a cap of 25); pills that would overlap other pills are left
 * out, the picked and the largest regions first, as the map leaves out labels that collide. A
 * click on a pill picks that region, as a click on its circle does.
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
  const candidates = inView;
  const gap = 2 * NODE_RADIUS + 3;
  // Every circle in view, with its label below it (as the label layer places it by default): a
  // column of pills must not cover another region's circle or its name and count.
  const circleBoxes = inView.map((f) => {
    const p = map.project(f.geometry.coordinates as [number, number]);
    const r = circleRadius(f.properties.total, top);
    const labelHalf = Math.max(30, f.properties.name.length * 3.8);
    return { path: f.properties.path, box: [Math.min(p.x - r, p.x - labelHalf), p.y - r, Math.max(p.x + r, p.x + labelHalf), p.y + r + 34] as [number, number, number, number] };
  });
  const overlaps = (a: [number, number, number, number], b: [number, number, number, number]) => a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
  // Where each region's column of pills would stand. Columns are placed the way the map places its
  // labels: the picked region first, then the largest; a column that would cover another column,
  // or another region's circle or label, is left out (its counts are in the list).
  const placed: { f: (typeof features)[number]; x: number; y: number; r: number; box: [number, number, number, number] }[] = [];
  const order = [...candidates].sort(
    (a, b) => Number(b.properties.path === focus) - Number(a.properties.path === focus) || b.properties.total - a.properties.total
  );
  for (const f of order) {
    const p = map.project(f.geometry.coordinates as [number, number]);
    const r = circleRadius(f.properties.total, top);
    const width = 14 + Math.max(...unitTypes.map((t) => pillWidth(compact.format(f.properties[t]))));
    const half = (unitTypes.length * gap) / 2;
    // The column stands to the circle's upper right, its last pill level with the circle's
    // centre, so it clears the region's own name and count below the circle.
    const box: [number, number, number, number] = [p.x + r, p.y - 2 * half + gap / 2, p.x + r + width, p.y + gap / 2];
    const clashes =
      placed.some((o) => overlaps(box, o.box)) ||
      circleBoxes.some((c) => c.path !== f.properties.path && overlaps(box, c.box));
    if (!clashes) placed.push({ f, x: p.x, y: p.y, r, box });
  }

  return (
    <svg className="pointer-events-none absolute inset-0 h-full w-full overflow-visible" aria-hidden={placed.length === 0} data-region-spiders="">
      {placed.map(({ f, x: px, y: py, r }) => {
        const p = { x: px, y: py };
        // The pills stand in a column to the circle's right, centred on it, each led to by a short
        // leg from the circle's rim.
        const left = p.x + r + 14;
        return (
          <g key={f.properties.path} data-region-spider={f.properties.path}>
            {unitTypes.map((t, i) => {
              const y = p.y - (unitTypes.length - 1 - i) * gap;
              const count = f.properties[t];
              const text = compact.format(count);
              const w = pillWidth(text);
              const label = `${f.properties.name}: ${count.toLocaleString()} ${UNIT_TYPE_LABEL[t].toLowerCase()}`;
              const a = Math.atan2(y - p.y, left - p.x);
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
                  <line x1={p.x + r * Math.cos(a)} y1={p.y + r * Math.sin(a)} x2={left} y2={y} stroke="#4b5563" strokeWidth={1.5} />
                  <rect
                    x={left}
                    y={y - NODE_RADIUS}
                    width={w}
                    height={2 * NODE_RADIUS}
                    rx={NODE_RADIUS}
                    fill={cssColour(`--color-${t}-500`)}
                    stroke="#ffffff"
                    strokeWidth={2}
                  />
                  <text x={left + w / 2} y={y} textAnchor="middle" dominantBaseline="central" fontSize={10} fontWeight={600} fill="#ffffff">
                    {text}
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
