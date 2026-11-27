"use client";

import { Check } from "lucide-react";

/** One measure the map can show: the number of units of the picked type, or a variable's total. */
export interface Measure {
  key: string;
  label: string;
}

/**
 * The map's measures (owner 2026-11-27 20:40: the simple thing is the default click, the refined
 * thing has its own spot). A click on a pill's name makes that measure the one the map shows and
 * sizes the circles by, and the only one shown. Each pill ends in a check box (owner 2026-11-27
 * 21:01, in place of a +): the primary's is checked, drawn inverted on its dark pill, and cannot
 * be unchecked; another's checks it to show it alongside, for the selection's figures and the
 * spider, and unchecks it to take it out.
 */
export function MeasurePicker({
  measures,
  selected,
  primary,
  onSelected,
  onPrimary,
}: {
  measures: readonly Measure[];
  selected: readonly string[];
  primary: string;
  onSelected: (next: string[]) => void;
  onPrimary: (key: string) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Measures" data-measure-picker="">
      {measures.map((m) => {
        const isPrimary = m.key === primary;
        const added = !isPrimary && selected.includes(m.key);
        return (
          <span
            key={m.key}
            className={`flex items-center rounded-lg border text-sm ${
              isPrimary
                ? "border-gray-900 bg-gray-900 text-white"
                : added
                  ? "border-gray-500 bg-gray-100 text-gray-900"
                  : "border-gray-200 bg-white text-gray-600 hover:bg-gray-50"
            }`}
            data-measure={m.key}
            data-measure-primary={isPrimary ? "" : undefined}
            data-measure-added={added ? "" : undefined}
          >
            <button
              type="button"
              className="px-2.5 py-1 font-medium"
              aria-pressed={isPrimary}
              title={isPrimary ? `The map shows ${m.label.toLowerCase()}` : `Show ${m.label.toLowerCase()} on the map`}
              onClick={() => {
                onPrimary(m.key);
                onSelected([m.key]);
              }}
            >
              {m.label}
            </button>
            {isPrimary ? (
              <span
                className="mr-2 flex h-4 w-4 items-center justify-center rounded-sm border border-white bg-white text-gray-900"
                title={`${m.label} is always shown: it sizes the circles`}
                aria-hidden
                data-measure-check={m.key}
              >
                <Check className="h-3 w-3" strokeWidth={3} />
              </span>
            ) : (
              <button
                type="button"
                role="checkbox"
                aria-checked={added}
                className={`mr-2 flex h-4 w-4 items-center justify-center rounded-sm border ${
                  added ? "border-gray-900 bg-gray-900 text-white" : "border-gray-400 bg-white hover:border-gray-900"
                }`}
                title={added ? `Stop showing ${m.label.toLowerCase()} alongside` : `Also show ${m.label.toLowerCase()}`}
                aria-label={added ? `Stop showing ${m.label.toLowerCase()} alongside` : `Also show ${m.label.toLowerCase()}`}
                onClick={() =>
                  onSelected(added ? selected.filter((k) => k !== m.key) : [...selected, m.key])
                }
                data-measure-check={m.key}
              >
                {added && <Check className="h-3 w-3" strokeWidth={3} />}
              </button>
            )}
          </span>
        );
      })}
    </div>
  );
}
