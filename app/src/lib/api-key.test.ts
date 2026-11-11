import { recreateApiKey, keyValidity } from "./api-key";

describe("keyValidity", () => {
  it("states the ISO expiry date and the whole days left", () => {
    expect(keyValidity("2027-03-27T12:00:00Z", new Date("2026-11-11T13:00:00Z"))).toEqual({
      validUntil: "2027-03-27",
      daysLeft: 135,
      expired: false,
    });
  });

  it("marks a key past its expiry as expired", () => {
    expect(keyValidity("2026-11-01T00:00:00Z", new Date("2026-11-11T00:00:00Z"))).toEqual({
      validUntil: "2026-11-01",
      daysLeft: 0,
      expired: true,
    });
  });

  it("has no expiry when the key has none", () => {
    expect(keyValidity(null, new Date("2026-11-11T00:00:00Z"))).toBeNull();
  });
});

// STATBUS-617: Recreate replaces the shown key with a new one of the same
// description and lifetime, then revokes the shown one, so a leaked token
// stops working and the user copies the new one.
function fakeClient(log: unknown[]) {
  return {
    rpc: (fn: string, args: Record<string, unknown>) => {
      log.push([fn, args]);
      if (fn === "create_api_key") {
        return Promise.resolve({ data: { jti: "new-jti", token: "new-token", description: args.description }, error: null });
      }
      if (fn === "revoke_api_key") return Promise.resolve({ data: true, error: null });
      return Promise.resolve({ data: null, error: { message: `unexpected ${fn}` } });
    },
  };
}

describe("recreateApiKey", () => {
  it("creates a key like the current one, then revokes the current one, and returns the new token", async () => {
    const log: unknown[] = [];
    const created = await recreateApiKey(fakeClient(log) as never, {
      jti: "old-jti",
      description: "Default API Key",
      created_at: "2026-01-01T00:00:00Z",
      expires_at: "2027-01-01T00:00:00Z",
    });
    expect(created).toEqual({ jti: "new-jti", token: "new-token" });
    expect(log).toEqual([
      ["create_api_key", { description: "Default API Key", duration: "365 days" }],
      ["revoke_api_key", { key_jti: "old-jti" }],
    ]);
  });

  it("keeps the current key when the new one cannot be created", async () => {
    const log: unknown[] = [];
    const client = {
      rpc: (fn: string, args: Record<string, unknown>) => {
        log.push([fn, args]);
        return Promise.resolve({ data: null, error: { message: "permission denied" } });
      },
    };
    await expect(
      recreateApiKey(client as never, { jti: "old-jti", description: "Default API Key", created_at: null, expires_at: null })
    ).rejects.toThrow("permission denied");
    expect(log).toEqual([["create_api_key", { description: "Default API Key", duration: "365 days" }]]);
  });
});
