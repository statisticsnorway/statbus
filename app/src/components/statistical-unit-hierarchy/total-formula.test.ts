import { establishmentValues, legalUnitTotalFormula } from "./total-formula";

describe("legalUnitTotalFormula (s465ff)", () => {
  it("writes a summed total as own + establishments", () => {
    expect(legalUnitTotalFormula(364, 369, [5])).toEqual({ text: "364 + 5", rule: "sum" });
  });
  it("writes a max total as max(own, establishments)", () => {
    expect(legalUnitTotalFormula(364, 364, [5])).toEqual({ text: "max(364, 5)", rule: "max" });
  });
  it("adds several establishments before comparing", () => {
    expect(legalUnitTotalFormula(5, 7, [4, 3])).toEqual({ text: "max(5, 7)", rule: "max" });
    expect(legalUnitTotalFormula(5, 12, [4, 3])).toEqual({ text: "5 + 7", rule: "sum" });
  });
  it("has nothing to explain without an establishment value", () => {
    expect(legalUnitTotalFormula(364, 364, [])).toBeUndefined();
  });
  it("groups thousands with a space", () => {
    expect(legalUnitTotalFormula(1200, 2500, [1300])).toEqual({ text: "1 200 + 1 300", rule: "sum" });
  });
});

describe("establishmentValues", () => {
  it("takes counted establishments' values of the variable only", () => {
    const unit = {
      establishment: [
        { status: { used_for_counting: true }, stat_for_unit: [{ stat_definition_id: 1, value_int: 5 }] },
        { status: { used_for_counting: false }, stat_for_unit: [{ stat_definition_id: 1, value_int: 9 }] },
        { status: { used_for_counting: true }, stat_for_unit: [{ stat_definition_id: 2, value_int: 7 }] },
      ],
    };
    expect(establishmentValues(unit, 1)).toEqual([5]);
  });
});
