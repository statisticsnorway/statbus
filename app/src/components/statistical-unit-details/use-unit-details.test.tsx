import { JSDOM } from "jsdom";
import { act, useState } from "react";
import { createRoot } from "react-dom/client";
import { Provider, createStore } from "jotai";
import { SWRConfig } from "swr";
import {
  useStatisticalUnitDetails,
  useStatisticalUnitHierarchy,
  useStatisticalUnitStats,
} from "./use-unit-details";

jest.mock("@/atoms/app-derived", () => ({
  useTimeFrame: () => ({ selectedTimeFrame: { valid_on: "2026-11-18" } }),
}));
jest.mock("./requests", () => ({
  getStatisticalUnitDetails: () => new Promise(() => {}),
  getStatisticalUnitStats: () => new Promise(() => {}),
  getStatisticalUnitHierarchy: () => new Promise(() => {}),
}));

// A form's save effect calls revalidate() after a successful save and lists
// revalidate in its dependencies, so revalidate keeps its identity while the
// component re-renders; a fresh function per render re-runs the effect after
// every refetch, an endless refetch loop (nst6hb, 2026-11-18: about 350
// requests per 5 s after one save on LU 29).
async function revalidateAcrossRerenders(useHook: () => { revalidate: unknown }) {
  const dom = new JSDOM("<!doctype html><div id=root></div>");
  Object.assign(globalThis, { window: dom.window, document: dom.window.document, IS_REACT_ACT_ENVIRONMENT: true });
  const seen: unknown[] = [];
  let rerender = () => {};
  function Probe() {
    const [, setTick] = useState(0);
    rerender = () => setTick((t) => t + 1);
    seen.push(useHook().revalidate);
    return null;
  }
  const root = createRoot(dom.window.document.getElementById("root")!);
  await act(async () => {
    root.render(
      <SWRConfig value={{ provider: () => new Map(), dedupingInterval: 0 }}>
        <Provider store={createStore()}>
          <Probe />
        </Provider>
      </SWRConfig>
    );
  });
  await act(async () => rerender());
  await act(async () => root.unmount());
  return seen;
}

describe("unit detail hooks keep revalidate stable across re-renders", () => {
  it.each([
    ["useStatisticalUnitDetails", () => useStatisticalUnitDetails("29", "legal_unit")],
    ["useStatisticalUnitStats", () => useStatisticalUnitStats("29", "legal_unit")],
    ["useStatisticalUnitHierarchy", () => useStatisticalUnitHierarchy("29", "legal_unit")],
  ])("%s", async (_name, useHook) => {
    const seen = await revalidateAcrossRerenders(useHook);
    expect(seen.length).toBeGreaterThanOrEqual(2);
    expect(seen.at(-1)).toBe(seen[0]);
  });
});
