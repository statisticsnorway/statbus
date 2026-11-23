"use client";

import { MAP_UNIT_TYPES, UNIT_TYPE_LABEL, UNIT_TYPE_SWATCH, type MapUnitType } from "./map-data";

/**
 * The map's legend: pick enterprises, legal units and establishments, each in its app colour,
 * with the number of units of that type shown (owner 2026-11-22, z2qt08). At least one type
 * stays picked.
 */
export function UnitTypeLegend({
  selected,
  onChange,
  totals,
  unitTypes = MAP_UNIT_TYPES,
  mixedSwatch = true,
}: {
  selected: readonly MapUnitType[];
  onChange: (next: MapUnitType[]) => void;
  totals: Record<MapUnitType, number>;
  /** The types this map can show; the Links map draws no enterprises (they have no place of their own). */
  unitTypes?: readonly MapUnitType[];
  /** Whether the map paints grey where types are counted together (the Regions map), so the legend explains grey. */
  mixedSwatch?: boolean;
}) {
  const toggle = (unitType: MapUnitType) => {
    const next = selected.includes(unitType) ? selected.filter((t) => t !== unitType) : [...selected, unitType];
    if (next.length > 0) onChange(unitTypes.filter((t) => next.includes(t)));
  };
  return (
    <fieldset className="space-y-1.5 text-sm" data-unit-type-legend="">
      <legend className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-500">Units</legend>
      {unitTypes.map((unitType) => (
        <label key={unitType} className="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            checked={selected.includes(unitType)}
            onChange={() => toggle(unitType)}
            data-unit-type={unitType}
          />
          <span
            className={`inline-block h-3 w-3 rounded-full border border-black/20 ${UNIT_TYPE_SWATCH[unitType]}`}
            aria-hidden
          />
          <span className="flex-1">{UNIT_TYPE_LABEL[unitType]}</span>
          <span className="tabular-nums text-gray-600">{totals[unitType].toLocaleString()}</span>
        </label>
      ))}
      {/* The grey line keeps its space when hidden, so ticking a second type does not move
          the legend (owner 2026-11-23). */}
      {mixedSwatch && (
        <p
          className={`flex items-center gap-2 pt-1 text-xs text-gray-600 ${selected.length > 1 ? "" : "invisible"}`}
          aria-hidden={selected.length <= 1}
          data-unit-type-mixed=""
        >
          <span className={`inline-block h-3 w-3 rounded-full border border-black/20 ${UNIT_TYPE_SWATCH.mixed}`} aria-hidden />
          Several types together
        </p>
      )}
    </fieldset>
  );
}
