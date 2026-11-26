/**
 * How wide a unit's history chart is (owner 2026-11-26): it grows with the number of observations
 * instead of filling the page, so one year is a small chart and many years use the room they need.
 * Each observation gets a fixed slot; the axes, title and legend take the rest. The result is a
 * CSS max-width in pixels; the chart still shrinks on a narrow screen.
 */
export const HISTORY_CHART_MIN_WIDTH_PX = 360;
export const HISTORY_CHART_MAX_WIDTH_PX = 1024;
/** Room for the axes on both sides, the title and the legend. */
const FRAME_PX = 160;
/** Room per observation: one column per visible series plus the gap between observations. */
const SLOT_PX = 48;

export function historyChartMaxWidth(observations: number): number {
  const wanted = FRAME_PX + Math.max(1, observations) * SLOT_PX;
  return Math.min(HISTORY_CHART_MAX_WIDTH_PX, Math.max(HISTORY_CHART_MIN_WIDTH_PX, wanted));
}

/** The widest a single column is drawn, so a few observations are bars and not slabs. */
export const HISTORY_CHART_MAX_COLUMN_PX = 32;
