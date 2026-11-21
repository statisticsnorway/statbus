import { primaryChain } from "./primary-chain";

// 64ae2w (owner 2026-11-20 and 2026-11-21): the chain is always in the order
// enterprise, legal unit, establishment, the same on all three pages, with
// the page's own unit marked current (its open "Notes", drawn on top).
const hierarchy = {
  enterprise: {
    id: 10,
    short_name: null,
    establishment: [],
    legal_unit: [
      {
        id: 20,
        name: "VERIDIT AS",
        primary_for_enterprise: true,
        establishment: [
          { id: 30, name: "VERIDIT AS avd Oslo", primary_for_legal_unit: true },
          { id: 31, name: "VERIDIT AS avd Bergen", primary_for_legal_unit: false },
        ],
      },
      { id: 21, name: "VERIDIT HOLDING AS", primary_for_enterprise: false, establishment: [{ id: 32, name: "Holding kontor", primary_for_legal_unit: true }] },
    ],
  },
};
const view = (chain: ReturnType<typeof primaryChain>) => chain.map((u) => `${u.kind} ${u.id} ${u.name}${u.current ? " (current)" : ""} ${u.href}`);

describe("primaryChain", () => {
  const order = [
    "Enterprise 10 VERIDIT AS /enterprises/10",
    "Primary legal unit 20 VERIDIT AS /legal-units/20",
    "Primary establishment 30 VERIDIT AS avd Oslo /establishments/30",
  ];

  it("from the enterprise page: enterprise (current), primary legal unit, primary establishment", () => {
    expect(view(primaryChain(hierarchy, { column: "enterprise_id", id: 10 }))).toEqual([
      "Enterprise 10 VERIDIT AS (current) /enterprises/10",
      order[1],
      order[2],
    ]);
  });

  it("from the primary legal unit's page: the same order, the legal unit current", () => {
    expect(view(primaryChain(hierarchy, { column: "legal_unit_id", id: 20 }))).toEqual([
      order[0],
      "Primary legal unit 20 VERIDIT AS (current) /legal-units/20",
      order[2],
    ]);
  });

  it("from the primary establishment's page: the same order, the establishment current", () => {
    expect(view(primaryChain(hierarchy, { column: "establishment_id", id: 30 }))).toEqual([
      order[0],
      order[1],
      "Primary establishment 30 VERIDIT AS avd Oslo (current) /establishments/30",
    ]);
  });

  it("from a non-primary establishment: it takes the establishment's place, named plainly", () => {
    expect(view(primaryChain(hierarchy, { column: "establishment_id", id: 31 }))).toEqual([
      order[0],
      order[1],
      "Establishment 31 VERIDIT AS avd Bergen (current) /establishments/31",
    ]);
  });

  it("from a non-primary legal unit: it and its own primary establishment take their places", () => {
    expect(view(primaryChain(hierarchy, { column: "legal_unit_id", id: 21 }))).toEqual([
      order[0],
      "Legal unit 21 VERIDIT HOLDING AS (current) /legal-units/21",
      "Primary establishment 32 Holding kontor /establishments/32",
    ]);
  });

  it("an informal enterprise: the enterprise, then its primary establishment, no legal unit", () => {
    const informal = { enterprise: { id: 11, short_name: null, legal_unit: [], establishment: [{ id: 40, name: "Kiosk", primary_for_enterprise: true }] } };
    expect(view(primaryChain(informal, { column: "enterprise_id", id: 11 }))).toEqual([
      "Enterprise 11 Kiosk (current) /enterprises/11",
      "Primary establishment 40 Kiosk /establishments/40",
    ]);
  });

  it("names the enterprise by its short name when it has one", () => {
    const named = { enterprise: { ...hierarchy.enterprise, short_name: "Veridit" } };
    expect(primaryChain(named, { column: "legal_unit_id", id: 20 })[0].name).toBe("Veridit");
  });

  it("without a hierarchy (not in the time frame): the page's own unit alone", () => {
    expect(view(primaryChain(null, { column: "legal_unit_id", id: 20 }, "VERIDIT AS"))).toEqual(["Legal unit 20 VERIDIT AS (current) /legal-units/20"]);
  });
});
