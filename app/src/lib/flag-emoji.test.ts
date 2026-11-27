import { flagEmoji } from "./flag-emoji";

describe("flagEmoji", () => {
  it("turns a country's two-letter code into its flag", () => {
    expect(flagEmoji("MZ")).toBe("🇲🇿");
    expect(flagEmoji("no")).toBe("🇳🇴");
  });

  it("gives no flag without a two-letter code", () => {
    expect([
      flagEmoji(null),
      flagEmoji(""),
      flagEmoji("NOR"),
      flagEmoji("1A"),
    ]).toEqual([null, null, null, null]);
  });
});
