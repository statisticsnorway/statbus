/**
 * A unit's history chart is as wide as its observations need (owner 2026-11-26): one year is a small
 * chart, a hundred years fill the readable maximum.
 */
import {
  HISTORY_CHART_MAX_WIDTH_PX,
  HISTORY_CHART_MIN_WIDTH_PX,
  historyChartMaxWidth,
} from "./history-chart-width";

describe("the width of a unit's history chart", () => {
  it("is small for one observation", () => {
    expect(historyChartMaxWidth(1)).toBe(HISTORY_CHART_MIN_WIDTH_PX);
  });

  it("grows with the observations", () => {
    expect(historyChartMaxWidth(10)).toBeGreaterThan(historyChartMaxWidth(5));
    expect(historyChartMaxWidth(10)).toBe(640);
  });

  it("stops at the readable maximum for many observations", () => {
    expect(historyChartMaxWidth(100)).toBe(HISTORY_CHART_MAX_WIDTH_PX);
  });

  it("treats no observations as one", () => {
    expect(historyChartMaxWidth(0)).toBe(HISTORY_CHART_MIN_WIDTH_PX);
  });
});
