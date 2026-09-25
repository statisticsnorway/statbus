import { NextRequest } from "next/server";
import { GET, exportOrder } from "./route";
import { getStatisticalUnits } from "@/app/search/search-requests";

jest.mock("@/app/search/search-requests", () => ({
  getStatisticalUnits: jest.fn(),
}));
jest.mock("@/context/RestClientStore", () => ({
  getServerRestClient: jest.fn().mockResolvedValue({}),
}));
jest.mock("@/context/BaseDataStore", () => ({
  baseDataStore: {
    getBaseData: jest
      .fn()
      .mockResolvedValue({ externalIdentTypes: [], statDefinitions: [] }),
  },
}));

const fetchUnits = jest.mocked(getStatisticalUnits);
const row = (id: number) =>
  ({
    name: `unit-${String(id).padStart(6, "0")}`,
    unit_id: id,
  }) as unknown as Awaited<
    ReturnType<typeof getStatisticalUnits>
  >["statisticalUnits"][number];

describe("search export", () => {
  beforeEach(() => fetchUnits.mockReset());

  it("uses temporal unit identity as a deterministic order tiebreaker", () => {
    expect(exportOrder(null)).toBe(
      "name.asc,unit_type.asc,unit_id.asc,valid_from.asc,valid_to.asc"
    );
    expect(exportOrder("unit_id.desc,name.desc")).toBe(
      "unit_id.desc,name.desc,unit_type.asc,valid_from.asc,valid_to.asc"
    );
  });

  it("assembles all CSV pages in order", async () => {
    const first = Array.from({ length: 100_000 }, (_, index) => row(index));
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: first,
      estimatedCount: 100_002,
    });
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: [row(100_000), row(100_001)],
      estimatedCount: 100_002,
    });
    const response = await GET(
      new NextRequest("http://localhost/api/search/export?format=csv")
    );
    const csv = await response.text();
    expect(response.status).toBe(200);
    expect(csv.split("\n")).toHaveLength(100_003);
    expect(csv).toContain("unit-000000,0\nunit-000001,1");
    expect(csv.endsWith("unit-100000,100000\nunit-100001,100001")).toBe(true);
    expect(fetchUnits).toHaveBeenCalledTimes(2);
    const secondParams = fetchUnits.mock.calls[1][1];
    expect(secondParams.get("offset")).toBe("100000");
    expect(secondParams.get("order")).toBe(exportOrder(null));
  });

  it("refuses XLSX beyond its row limit and recommends CSV", async () => {
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: [row(1)],
      estimatedCount: 1_048_576,
    });
    const response = await GET(
      new NextRequest("http://localhost/api/search/export?format=xlsx")
    );
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({
      message: expect.stringContaining("Use CSV instead"),
    });
    expect(fetchUnits).toHaveBeenCalledTimes(1);
  });

  it("refuses XLSX when the exact count is unavailable", async () => {
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: [row(1)],
      estimatedCount: null,
    });
    const response = await GET(
      new NextRequest("http://localhost/api/search/export?format=xlsx")
    );
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({
      message: expect.stringContaining("Use CSV instead"),
    });
    expect(fetchUnits).toHaveBeenCalledTimes(1);
  });

  it("refuses XLSX when a later page grows beyond the sheet limit", async () => {
    const first = Array.from({ length: 100_000 }, (_, index) => row(index));
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: first,
      estimatedCount: 1_048_575,
    });
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: Array(948_576).fill(row(1)),
      estimatedCount: 1_048_576,
    });
    const response = await GET(
      new NextRequest("http://localhost/api/search/export?format=xlsx")
    );
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({
      message: expect.stringContaining("Use CSV instead"),
    });
    expect(fetchUnits).toHaveBeenCalledTimes(2);
  });

  it("stops at the initial count even when the last page is full", async () => {
    const first = Array.from({ length: 100_000 }, (_, index) => row(index));
    fetchUnits.mockResolvedValueOnce({
      statisticalUnits: first,
      estimatedCount: 100_000,
    });
    const response = await GET(
      new NextRequest("http://localhost/api/search/export?format=csv")
    );
    expect((await response.text()).split("\n")).toHaveLength(100_001);
    expect(fetchUnits).toHaveBeenCalledTimes(1);
  });
});
