import { createStore } from "jotai";
import {
  artifactSHAAtom,
  refreshRunningIdentityAtom,
  runningIdentityAtom,
} from "@/atoms/running-identity";
import {
  parseArtifactSHA,
  parseRunningIdentity,
  runningVersionDisplay,
  type RunningIdentity,
} from "./running-identity";

const source = "a".repeat(40);
const target = "b".repeat(40);
const identity: RunningIdentity = {
  commit_sha: source,
  resolved_name: "v2026.09.0",
  release_status: "release",
  build_name: "v2026.09.0-rc.14",
};
const response = (payload: unknown, ok = true) =>
  ({ ok, json: async () => payload }) as Response;

describe("artifact-bound release metadata", () => {
  afterEach(() => jest.restoreAllMocks());

  test("legacy, short, dirty/unproven artifact cannot claim configured identity", () => {
    for (const value of [
      null,
      {},
      { commit_sha: null },
      { commit_sha: "abcdef12" },
      { commit_sha: target + "-dirty" },
    ]) {
      expect(parseArtifactSHA(value)).toBeNull();
    }
    expect(runningVersionDisplay(null, null)).toEqual({
      name: "unknown",
      commit: null,
    });
  });

  test("exact shape, cardinality and equality required", () => {
    for (const rows of [
      [],
      [identity, identity],
      [{ ...identity, commit_sha: target }],
      [{ ...identity, release_status: "bad" }],
      [{ ...identity, release_status: ["release"] }],
      [{ ...identity, resolved_name: " " }],
      [{ ...identity, resolved_name: "" }],
      [{ ...identity, build_name: 42 }],
    ]) {
      expect(parseRunningIdentity(rows, source)).toBeNull();
    }
    expect(parseRunningIdentity([identity], source)).toEqual(identity);
    expect(parseRunningIdentity([identity], null)).toBeNull();
  });

  test("pruned metadata retains positive full artifact proof", () => {
    expect(runningVersionDisplay(null, source)).toEqual({
      name: "unknown",
      commit: "aaaaaaaa",
    });
  });

  test("open tab follows restored source app, not configured target program", async () => {
    const fetchMock = jest
      .spyOn(global, "fetch")
      .mockResolvedValueOnce(response({ commit_sha: target }))
      .mockResolvedValueOnce(response([{ ...identity, commit_sha: target }]))
      .mockResolvedValueOnce(response({ commit_sha: source }))
      .mockResolvedValueOnce(response([identity]));
    const store = createStore();
    await store.set(refreshRunningIdentityAtom);
    expect(store.get(artifactSHAAtom)).toBe(target);
    await store.set(refreshRunningIdentityAtom);
    expect(store.get(artifactSHAAtom)).toBe(source);
    expect(store.get(runningIdentityAtom)).toEqual(identity);
    expect(fetchMock).toHaveBeenCalledWith("/_statbus-build.json", {
      cache: "no-store",
    });
    expect(fetchMock).toHaveBeenCalledWith(
      `/rest/rpc/release_identity?p_commit_sha=${source}`,
      { credentials: "include", cache: "no-store" }
    );
  });

  test.each(
    [
      [],
      [{ ...identity, commit_sha: target }],
      [identity, identity],
      [{ ...identity, resolved_name: 42 }],
    ].map((rows) => [rows])
  )(
    "unproven metadata keeps the last proven label for the same artifact: %j",
    async (rows) => {
      jest
        .spyOn(global, "fetch")
        .mockResolvedValueOnce(response({ commit_sha: source }))
        .mockResolvedValueOnce(response(rows));
      const store = createStore();
      store.set(runningIdentityAtom, identity);
      await store.set(refreshRunningIdentityAtom);
      expect(store.get(artifactSHAAtom)).toBe(source);
      // STATBUS-455: keep the last PROVEN label until a new one is proven —
      // blanking it here flashed "unknown <full sha>" on every 30s refresh.
      expect(store.get(runningIdentityAtom)).toEqual(identity);
    }
  );

  test("unproven metadata clears the old label when the artifact itself changed", async () => {
    jest
      .spyOn(global, "fetch")
      .mockResolvedValueOnce(response({ commit_sha: target }))
      .mockResolvedValueOnce(response([]));
    const store = createStore();
    store.set(runningIdentityAtom, identity);
    await store.set(refreshRunningIdentityAtom);
    expect(store.get(artifactSHAAtom)).toBe(target);
    // An old label must never describe a new artifact.
    expect(store.get(runningIdentityAtom)).toBeNull();
  });

  test("promotion changes label without rewriting artifact/build provenance", async () => {
    jest
      .spyOn(global, "fetch")
      .mockResolvedValueOnce(response({ commit_sha: source }))
      .mockResolvedValueOnce(
        response([
          { ...identity, resolved_name: "rc.14", release_status: "prerelease" },
        ])
      )
      .mockResolvedValueOnce(response({ commit_sha: source }))
      .mockResolvedValueOnce(response([identity]));
    const store = createStore();
    await store.set(refreshRunningIdentityAtom);
    await store.set(refreshRunningIdentityAtom);
    expect(store.get(artifactSHAAtom)).toBe(source);
    expect(store.get(runningIdentityAtom)).toEqual(identity);
  });

  test("missing old artifact clears proof and does not ask history", async () => {
    const fetchMock = jest
      .spyOn(global, "fetch")
      .mockResolvedValue(response(null, false));
    const store = createStore();
    store.set(artifactSHAAtom, target);
    store.set(runningIdentityAtom, identity);
    await store.set(refreshRunningIdentityAtom);
    expect(store.get(artifactSHAAtom)).toBeNull();
    expect(store.get(runningIdentityAtom)).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
