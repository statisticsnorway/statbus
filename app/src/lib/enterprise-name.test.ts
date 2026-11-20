import { derivedEnterpriseName, enterpriseName } from "./enterprise-name";

const legalUnits = [
  { primary_for_enterprise: false, name: "Statistics Norway Bergen" },
  { primary_for_enterprise: true, name: "Statistics Norway" },
];

describe("enterpriseName", () => {
  it("is the enterprise's short name when set", () => {
    expect(enterpriseName({ short_name: "SSB", legal_unit: legalUnits })).toBe(
      "SSB"
    );
  });

  it("is the primary legal unit's name when the short name is empty", () => {
    expect(enterpriseName({ short_name: null, legal_unit: legalUnits })).toBe(
      "Statistics Norway"
    );
    expect(enterpriseName({ short_name: "  ", legal_unit: legalUnits })).toBe(
      "Statistics Norway"
    );
  });

  it("falls back to the primary establishment of an enterprise without legal units", () => {
    expect(
      enterpriseName({
        short_name: null,
        establishment: [{ primary_for_enterprise: true, name: "Corner Shop" }],
      })
    ).toBe("Corner Shop");
  });
});

describe("derivedEnterpriseName", () => {
  it("ignores the short name", () => {
    expect(derivedEnterpriseName({ legal_unit: legalUnits })).toBe(
      "Statistics Norway"
    );
  });
});
