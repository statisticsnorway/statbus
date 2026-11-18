import { createStore } from "jotai";
import {
  numberOfRegionsAtomAsync,
  refreshGettingStartedAtom,
  settingsAtomAsync,
} from "./getting-started";

// 50bwaz: after a reset the Getting started menu shows what the database
// holds. The step atoms cache their first answer, so a reset that leaves them
// as they were keeps ticking steps whose rows are gone (North Cyprus,
// 2026-11-18: country and NACE 2.1 ticked, settings empty, the custom code
// upload refused).
const db = { settings: [{ country: { id: 1, name: "Norway", iso_2: "NO" } }] as unknown[], regions: 94 };

jest.mock("./auth", () => {
  const { atom } = jest.requireActual("jotai");
  return { authStateForDataFetchingAtom: atom("authenticated") };
});
jest.mock("./rest-client", () => {
  const { atom } = jest.requireActual("jotai");
  const query = (table: string) => {
    const result = () =>
      table === "settings"
        ? Promise.resolve({ data: db.settings, error: null })
        : Promise.resolve({ count: db.regions, error: null });
    const builder = { select: () => builder, limit: result, then: (f: (v: unknown) => unknown) => result().then(f) };
    return builder;
  };
  return { restClientAtom: atom({ from: query }) };
});
jest.mock("./base-data", () => {
  const { atom } = jest.requireActual("jotai");
  return { refreshBaseDataAtom: atom(null, () => {}) };
});

describe("refreshGettingStartedAtom", () => {
  it("makes every Getting started step read the database again", async () => {
    const store = createStore();
    expect(await store.get(settingsAtomAsync)).toEqual(db.settings[0]);
    expect(await store.get(numberOfRegionsAtomAsync)).toBe(94);

    db.settings = [];
    db.regions = 0;
    expect(await store.get(settingsAtomAsync)).not.toBeNull();

    store.set(refreshGettingStartedAtom);
    expect(await store.get(settingsAtomAsync)).toBeNull();
    expect(await store.get(numberOfRegionsAtomAsync)).toBe(0);
  });
});
