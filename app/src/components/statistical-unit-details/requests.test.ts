import { getStatisticalUnitHierarchy } from "./requests";
import { getBrowserRestClient } from "@/context/RestClientStore";

jest.mock("@/context/RestClientStore", () => ({ getBrowserRestClient: jest.fn(), getServerRestClient: jest.fn() }));

// public.statistical_unit_hierarchy returns {} for a unit that does not exist
// on the asked date (owner 2026-11-18: LU 31 from 2026-05-01, viewed in the
// Previous frame (2025)). That is "not in this time frame", not an error.
function clientReturning(data: unknown) {
  const single = { returns: () => Promise.resolve({ data, error: null }) };
  return { rpc: () => ({ single: () => single }) };
}

describe("getStatisticalUnitHierarchy", () => {
  it("answers no hierarchy and no error for a unit absent on the date", async () => {
    (getBrowserRestClient as jest.Mock).mockResolvedValue(clientReturning({}));
    expect(await getStatisticalUnitHierarchy(31, "legal_unit", "2025-12-31")).toEqual({ hierarchy: null, error: null });
  });
  it("answers no hierarchy and no error when the function returns nothing", async () => {
    (getBrowserRestClient as jest.Mock).mockResolvedValue(clientReturning(null));
    expect(await getStatisticalUnitHierarchy(31, "legal_unit", "2025-12-31")).toEqual({ hierarchy: null, error: null });
  });
  it("returns the hierarchy of a unit that exists", async () => {
    const hierarchy = { enterprise: { id: 1, legal_unit: [] } };
    (getBrowserRestClient as jest.Mock).mockResolvedValue(clientReturning(hierarchy));
    expect(await getStatisticalUnitHierarchy(29, "legal_unit", "2026-11-18")).toEqual({ hierarchy, error: null });
  });
});
