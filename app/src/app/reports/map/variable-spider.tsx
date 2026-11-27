"use client";

import { useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

/** One measure of the picked region, drawn as a node on a leg round it. */
export interface SpiderMeasure {
  key: string;
  /** Short name on the node: "Enterprises", "Employees". */
  label: string;
  value: number;
  /** A second line under the value: the mean and how many units carry the variable. */
  detail?: string;
  colour: string;
}

const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });
const NODE_W = 92;
const NODE_H = 40;

/**
 * Several statistical variables of one region at once, round its circle (owner 2026-11-27,
 * ppvxg2): the hub stays on the region with its name; a leg leads to one node per measure, the
 * number of units first and then each picked variable's total, as the unit map's spider pulls a
 * stack's units out round their place. The circles size the regions by one measure; the spider
 * shows the others for the region in focus. It follows the map as it moves and closes on Escape.
 */
export function VariableSpider({
  map,
  coordinates,
  name,
  measures,
  onClose,
}: {
  map: MapLibreMap;
  coordinates: [number, number];
  name: string;
  measures: SpiderMeasure[];
  onClose: () => void;
}) {
  const [hub, setHub] = useState(() => map.project(coordinates));
  useGuardedEffect(
    () => {
      setHub(map.project(coordinates));
      const follow = () => setHub(map.project(coordinates));
      const closeOnEscape = (e: KeyboardEvent) => e.key === "Escape" && onClose();
      map.on("move", follow);
      document.addEventListener("keydown", closeOnEscape);
      return () => {
        map.off("move", follow);
        document.removeEventListener("keydown", closeOnEscape);
      };
    },
    [map, coordinates, onClose],
    "VariableSpider:follow"
  );

  const radius = 70 + Math.max(0, measures.length - 4) * 10;
  const size = 2 * (radius + NODE_W);
  const c = size / 2;
  const nodes = measures.map((m, i) => {
    const angle = (2 * Math.PI * i) / measures.length - Math.PI / 2;
    return { ...m, x: radius * Math.cos(angle), y: radius * Math.sin(angle) };
  });
  return (
    <svg
      className="pointer-events-none absolute z-10 overflow-visible"
      style={{ left: hub.x - c, top: hub.y - c }}
      width={size}
      height={size}
      role="group"
      aria-label={`${name}: ${measures.map((m) => `${m.label} ${m.value.toLocaleString()}`).join(", ")}`}
      data-variable-spider=""
    >
      {nodes.map((n) => (
        <line key={`leg-${n.key}`} x1={c} y1={c} x2={c + n.x} y2={c + n.y} stroke="#4b5563" strokeWidth={1.5} />
      ))}
      <circle cx={c} cy={c} r={7} fill="#111827" stroke="#ffffff" strokeWidth={2} />
      {nodes.map((n) => (
        <g key={n.key} data-spider-measure={n.key}>
          <title>{`${n.label}: ${n.value.toLocaleString()}${n.detail ? ` (${n.detail})` : ""}`}</title>
          <rect
            x={c + n.x - NODE_W / 2}
            y={c + n.y - NODE_H / 2}
            width={NODE_W}
            height={NODE_H}
            rx={8}
            fill="#ffffff"
            stroke={n.colour}
            strokeWidth={2.5}
          />
          <text x={c + n.x} y={c + n.y - 6} textAnchor="middle" fontSize={13} fontWeight={700} fill="#111827">
            {compact.format(n.value)}
          </text>
          <text x={c + n.x} y={c + n.y + 10} textAnchor="middle" fontSize={11} fill="#4b5563">
            {n.label}
          </text>
        </g>
      ))}
    </svg>
  );
}
