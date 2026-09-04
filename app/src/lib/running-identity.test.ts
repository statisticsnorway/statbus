import { createStore } from "jotai";
import {
  refreshRunningIdentityAtom,
  runningIdentityAtom,
} from "@/atoms/running-identity";
import {
  parseRunningIdentity,
  runningVersionDisplay,
  type RunningIdentity,
} from "./running-identity";

const promotedIdentity: RunningIdentity = {
  commit_sha: "d53731ec539b03b9378ff8828bb2be938d9e2e0f",
  resolved_name: "v2026.09.0",
  release_status: "release",
  build_name: "v2026.09.0-rc.14",
};

describe("running identity", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  test("uses the resolved current name while retaining the running commit", () => {
    expect(
      runningVersionDisplay(promotedIdentity, "v2026.09.0-rc.14", "d53731ec")
    ).toEqual({ name: "v2026.09.0", commit: "d53731ec" });
  });

  test("falls back to injected build/install identity when resolution is unavailable", () => {
    expect(runningVersionDisplay(null, "v2026.09.0-rc.14", "d53731ec")).toEqual(
      { name: "v2026.09.0-rc.14", commit: "d53731ec" }
    );
  });

  test("rejects missing or malformed resolver rows", () => {
    expect(parseRunningIdentity([])).toBeNull();
    expect(parseRunningIdentity([{ resolved_name: "v2026.09.0" }])).toBeNull();
  });

  test("fetches the public REST resolver into the Jotai atom", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => [promotedIdentity],
    } as Response);
    const store = createStore();

    await store.set(refreshRunningIdentityAtom);

    expect(fetchMock).toHaveBeenCalledWith("/rest/rpc/running_identity", {
      credentials: "include",
    });
    expect(store.get(runningIdentityAtom)).toEqual(promotedIdentity);
  });

  test("clears a stale resolved value when REST becomes unavailable", async () => {
    jest.spyOn(global, "fetch").mockRejectedValue(new Error("offline"));
    const store = createStore();
    store.set(runningIdentityAtom, promotedIdentity);

    await store.set(refreshRunningIdentityAtom);

    expect(store.get(runningIdentityAtom)).toBeNull();
  });
});
