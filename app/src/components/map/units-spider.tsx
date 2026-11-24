"use client";

import { useState } from "react";
import type { Map as MapLibreMap } from "maplibre-gl";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { spiderNodes, type UnitPointProperties } from "./map-data";
import { cssColour } from "./unit-map";

/** A stack of units at one place, opened as a spider: where it is and what it holds. */
export interface SpiderStack {
  coordinates: [number, number];
  units: UnitPointProperties[];
}

const NODE_RADIUS = 14;
/** Stacks of this many units or fewer open with one node per unit. */
const PER_UNIT_UP_TO = 8;

/** The hub's radius: the radius the map draws the stack's circle with (units-map.tsx unit-groups), so it covers it. */
function hubRadius(count: number): number {
  return Math.min(30, Math.max(10, 10 + ((Math.sqrt(count) - 1) / 19) * 20));
}

/**
 * The spider over the units map (owner 2026-11-24, z2qt08): a click on a stack of units that
 * share one place opens it. The hub stays on the place with the stack's total; legs lead to one
 * node per unit type and placement (or per unit, for a small stack), each in its type's colour,
 * solid for units at their address and a ring for units somewhere in the region, with its count.
 * The legs show the nodes are pulled out from one place, not where their units are. A click on
 * a node lists its units, on the hub all of them. It follows the map as it moves; the page
 * closes it on a click elsewhere, Escape or a new selection.
 */
export function UnitsSpider({
  map,
  stack,
  selectedKey,
  focusedUnit = null,
  onPick,
  onClose,
}: {
  map: MapLibreMap;
  stack: SpiderStack;
  /** The node whose units are listed, or null for the hub (all of them). */
  selectedKey: string | null;
  /** The unit picked in the list ("legal_unit:20"): its node is marked. */
  focusedUnit?: string | null;
  onPick: (key: string | null, units: UnitPointProperties[]) => void;
  onClose: () => void;
}) {
  const [hub, setHub] = useState(() => map.project(stack.coordinates));
  useGuardedEffect(
    () => {
      const follow = () => setHub(map.project(stack.coordinates));
      const closeOnEscape = (e: KeyboardEvent) => e.key === "Escape" && onClose();
      map.on("move", follow);
      // Zooming regroups the units, so the stack this spider opened may no longer be one circle.
      map.on("zoomstart", onClose);
      document.addEventListener("keydown", closeOnEscape);
      return () => {
        map.off("move", follow);
        map.off("zoomstart", onClose);
        document.removeEventListener("keydown", closeOnEscape);
      };
    },
    [map, stack, onClose],
    "UnitsSpider:follow"
  );

  const hubR = hubRadius(stack.units.length);
  // A small stack has one node per unit, drawn as the unit's marker; a larger one has one node
  // per kind, each with its count, "1" included (spiderNodes' perUnitUpTo).
  const perUnit = stack.units.length <= PER_UNIT_UP_TO;
  const nodes = spiderNodes(stack.units, { perUnitUpTo: PER_UNIT_UP_TO, radius: hubR + NODE_RADIUS + 26 });
  const size = 2 * (hubR + 2 * NODE_RADIUS + 30);
  const c = size / 2;
  const colourOf = (unitType: string) => cssColour(`--color-${unitType}-500`);
  return (
    <svg
      className="pointer-events-none absolute z-10 overflow-visible"
      style={{ left: hub.x - c, top: hub.y - c }}
      width={size}
      height={size}
      role="group"
      aria-label={`${stack.units.length} units at one place`}
      data-units-spider=""
    >
      {nodes.map((n) => (
        <line key={`leg-${n.key}`} x1={c} y1={c} x2={c + n.x} y2={c + n.y} stroke="#4b5563" strokeWidth={1.5} />
      ))}
      <g
        className="pointer-events-auto cursor-pointer"
        onClick={() => onPick(null, stack.units)}
        role="button"
        aria-label={`All ${stack.units.length} units here`}
        data-spider-hub=""
      >
        <circle cx={c} cy={c} r={hubR} fill="#ffffff" stroke="#111827" strokeWidth={selectedKey === null ? 3 : 2} />
        <text x={c} y={c} textAnchor="middle" dominantBaseline="central" fontSize={12} fontWeight={600} fill="#111827">
          {stack.units.length}
        </text>
      </g>
      {nodes.map((n) => {
        const colour = colourOf(n.unit_type);
        const solid = n.placed === "point";
        const single = perUnit;
        const label = single
          ? `${n.units[0].name}, ${n.unit_type === "legal_unit" ? "legal unit" : "establishment"}`
          : `${n.units.length} ${n.unit_type === "legal_unit" ? (n.units.length === 1 ? "legal unit" : "legal units") : n.units.length === 1 ? "establishment" : "establishments"} ${solid ? "at the address" : "somewhere in the region"}`;
        return (
          <g
            key={n.key}
            className="pointer-events-auto cursor-pointer"
            onClick={() => onPick(n.key, n.units)}
            role="button"
            aria-label={label}
            data-spider-node={n.key}
          >
            <title>{label}</title>
            {/* The listed node, or the node holding the unit picked in the list, gets a dark ring
                outside its own, so its type colour stays. */}
            {(selectedKey === n.key || n.units.some((u) => `${u.unit_type}:${u.id}` === focusedUnit)) && (
              <circle cx={c + n.x} cy={c + n.y} r={(single ? 8 : NODE_RADIUS) + 4} fill="none" stroke="#111827" strokeWidth={2} />
            )}
            <circle
              cx={c + n.x}
              cy={c + n.y}
              r={single ? 8 : NODE_RADIUS}
              fill={solid ? colour : "#ffffff"}
              stroke={solid ? "#ffffff" : colour}
              strokeWidth={2.5}
            />
            {!single && (
              <text
                x={c + n.x}
                y={c + n.y}
                textAnchor="middle"
                dominantBaseline="central"
                fontSize={12}
                fontWeight={600}
                fill={solid ? "#ffffff" : "#111827"}
              >
                {n.units.length}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
