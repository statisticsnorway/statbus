import { createStore } from "jotai";
import {
  artifactSHAAtom,
  refreshRunningIdentityAtom,
  runningIdentityAtom,
} from "./running-identity";
import type { RunningIdentity } from "@/lib/running-identity";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);

const identityA: RunningIdentity = {
  commit_sha: SHA_A,
  resolved_name: "v2026.10.0-rc.20",
  release_status: "prerelease",
  build_name: null,
};

function mockFetch(handlers: {
  artifactSHA: string | null;
  identityOk: boolean;
}) {
  return jest.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = String(input);
    if (url.includes("/_statbus-build.json")) {
      return {
        ok: handlers.artifactSHA !== null,
        json: async () => ({ commit_sha: handlers.artifactSHA }),
      } as Response;
    }
    if (url.includes("/rest/rpc/release_identity")) {
      return {
        ok: handlers.identityOk,
        json: async () => [
          {
            commit_sha: handlers.artifactSHA,
            resolved_name: "v2026.10.0-rc.21",
            release_status: "prerelease",
            build_name: null,
          },
        ],
      } as Response;
    }
    throw new Error(`unexpected fetch: ${url}`);
  });
}

afterEach(() => {
  jest.restoreAllMocks();
});

test("a healthy refresh replaces the label with the newly proven one", async () => {
  const store = createStore();
  store.set(runningIdentityAtom, identityA);
  mockFetch({ artifactSHA: SHA_A, identityOk: true });
  await store.set(refreshRunningIdentityAtom);
  expect(store.get(runningIdentityAtom)?.resolved_name).toBe(
    "v2026.10.0-rc.21"
  );
});

test("the last proven label survives a failed identity refresh on the same artifact", async () => {
  const store = createStore();
  store.set(artifactSHAAtom, SHA_A);
  store.set(runningIdentityAtom, identityA);
  mockFetch({ artifactSHA: SHA_A, identityOk: false });
  await store.set(refreshRunningIdentityAtom);
  // Same artifact, no new proof: keep the old label rather than flashing
  // "unknown" on every 30s poll.
  expect(store.get(runningIdentityAtom)).toEqual(identityA);
});

test("an old label never describes a new artifact", async () => {
  const store = createStore();
  store.set(artifactSHAAtom, SHA_A);
  store.set(runningIdentityAtom, identityA);
  mockFetch({ artifactSHA: SHA_B, identityOk: false });
  await store.set(refreshRunningIdentityAtom);
  expect(store.get(artifactSHAAtom)).toBe(SHA_B);
  expect(store.get(runningIdentityAtom)).toBeNull();
});

test("a vanished artifact clears both sha and label", async () => {
  const store = createStore();
  store.set(artifactSHAAtom, SHA_A);
  store.set(runningIdentityAtom, identityA);
  mockFetch({ artifactSHA: null, identityOk: false });
  await store.set(refreshRunningIdentityAtom);
  expect(store.get(artifactSHAAtom)).toBeNull();
  expect(store.get(runningIdentityAtom)).toBeNull();
});
