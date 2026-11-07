import { atom, createStore } from "jotai";
import {
  setWorkerStatusAtom,
  workerStatusAtom,
  type PhaseProgress,
} from "./worker_status";

jest.mock("./base-data", () => ({
  refreshBaseDataAtom: atom(null, () => {}),
  invalidateHasStatisticalUnitsCache: jest.fn(),
}));
jest.mock("@/components/estimated-count", () => ({
  invalidateExactCountsCache: jest.fn(),
  exactCountCacheGenerationAtom: atom(0),
}));
jest.mock("./search", () => ({ searchPageDataReadyAtom: atom(false) }));
jest.mock("./rest-client", () => ({ restClientAtom: atom(null) }));
jest.mock("./auth", () => ({ isAuthenticatedStrictAtom: atom(false) }));

const pending: PhaseProgress = {
  phase: "is_deriving_reports",
  active: false,
  pending: true,
  step: null,
  total: 0,
  completed: 0,
  effective_establishment_count: 0,
  effective_legal_unit_count: 24000,
  effective_enterprise_count: 24000,
  effective_power_group_count: 0,
};

function waitingStore() {
  const store = createStore();
  store.set(setWorkerStatusAtom, {
    type: "pipeline_progress",
    phases: [pending],
  });
  return store;
}

test("reports advances from waiting through boolean start, detailed progress and idle", () => {
  const store = waitingStore();
  expect(store.get(workerStatusAtom).derivingReports).toMatchObject({
    active: false,
    pending: true,
  });
  store.set(setWorkerStatusAtom, { type: "is_deriving_reports", status: true });
  expect(store.get(workerStatusAtom).derivingReports).toMatchObject({
    active: true,
    pending: false,
    effective_legal_unit_count: 24000,
  });
  store.set(setWorkerStatusAtom, {
    type: "pipeline_progress",
    phases: [
      {
        ...pending,
        active: true,
        pending: false,
        step: "statistical_unit_facet_reduce",
        total: 4,
        completed: 2,
      },
    ],
  });
  expect(store.get(workerStatusAtom).derivingReports).toMatchObject({
    active: true,
    step: "statistical_unit_facet_reduce",
    total: 4,
    completed: 2,
  });
  store.set(setWorkerStatusAtom, {
    type: "is_deriving_reports",
    status: false,
  });
  expect(store.get(workerStatusAtom)).toMatchObject({
    isDerivingReports: false,
    derivingReports: null,
  });
});

test("boolean lifecycle reaches idle when structured running notifications are dropped", () => {
  const store = waitingStore();
  store.set(setWorkerStatusAtom, { type: "is_deriving_reports", status: true });
  store.set(setWorkerStatusAtom, {
    type: "is_deriving_reports",
    status: false,
  });
  expect(store.get(workerStatusAtom)).toMatchObject({
    isDerivingReports: false,
    derivingReports: null,
  });
});

test("a boolean start after structured progress preserves the running step", () => {
  const store = waitingStore();
  store.set(setWorkerStatusAtom, {
    type: "pipeline_progress",
    phases: [
      {
        ...pending,
        active: true,
        pending: false,
        step: "statistical_unit_facet_reduce",
        total: 4,
        completed: 2,
      },
    ],
  });
  store.set(setWorkerStatusAtom, { type: "is_deriving_reports", status: true });
  expect(store.get(workerStatusAtom).derivingReports).toMatchObject({
    active: true,
    pending: false,
    step: "statistical_unit_facet_reduce",
    total: 4,
    completed: 2,
  });
});

test("idle units signal preserves queued reports until their own start", () => {
  const store = waitingStore();
  store.set(setWorkerStatusAtom, {
    type: "is_deriving_statistical_units",
    status: false,
  });
  expect(store.get(workerStatusAtom).derivingReports).toMatchObject({
    active: false,
    pending: true,
  });
});
