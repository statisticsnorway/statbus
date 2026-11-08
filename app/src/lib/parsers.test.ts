import { z } from "zod";
import { getFiltersStateParser, getSortingStateParser } from "@/lib/parsers";

// Load Nuqs' actual ESM implementation through Node, outside Jest's CJS loader.
jest.mock("nuqs/server", () => {
  return process.getBuiltinModule("module").createRequire(__filename)(
    "nuqs/server"
  );
});

const rawCodeUnitLimit = 64 * 1024;
const rootItemLimit = 128;
const filterValueLimit = 256;

const sorting = getSortingStateParser<Record<string, unknown>>();
const filters = getFiltersStateParser<Record<string, unknown>>();
const filter = (value: string | string[] = "registered") => ({
  id: "status",
  value,
  variant: "multiSelect" as const,
  operator: "inArray" as const,
  filterId: "status-filter",
});

const sortingRaw = (length: number) => {
  const envelope = JSON.stringify([{ id: "", desc: false }]);
  return JSON.stringify([
    { id: "é".repeat(length - envelope.length), desc: false },
  ]);
};
const filterRaw = (length: number) => {
  const envelope = JSON.stringify([filter("")]);
  return JSON.stringify([filter("é".repeat(length - envelope.length))]);
};

afterEach(() => jest.restoreAllMocks());

describe("bounded query-state parsers", () => {
  test.each([
    ["sorting", sorting, sortingRaw],
    ["filters", filters, filterRaw],
  ] as const)(
    "%s accepts exactly 64Ki UTF-16 code units and rejects the next code unit before JSON parsing",
    (_name, parser, raw) => {
      const boundary = raw(rawCodeUnitLimit);
      expect(boundary.length).toBe(rawCodeUnitLimit);
      expect(Buffer.byteLength(boundary, "utf8")).toBeGreaterThan(
        rawCodeUnitLimit
      );
      const parsed = parser.parse(boundary);
      expect(parsed).toEqual(JSON.parse(boundary));

      const oversized = raw(rawCodeUnitLimit + 1);
      const decode = jest.spyOn(JSON, "parse");
      const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
      expect(parser.parse(oversized)).toBeNull();
      expect(decode).toHaveBeenCalledTimes(0);
      expect(traverse).toHaveBeenCalledTimes(0);
    }
  );

  test("sorting roundtrips 128 rows and rejects 129 rows before Zod traversal", () => {
    const boundary = Array.from({ length: rootItemLimit }, (_, index) => ({
      id: `column-${index}`,
      desc: index % 2 === 0,
    }));
    expect(sorting.parse(sorting.serialize(boundary))).toEqual(boundary);

    const oversized = JSON.stringify([
      ...boundary,
      { id: "extra", desc: false },
    ]);
    const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
    expect(sorting.parse(oversized)).toBeNull();
    expect(traverse).toHaveBeenCalledTimes(0);
  });

  test("filters roundtrip 128 rows and reject 129 rows before Zod traversal", () => {
    const boundary = Array.from({ length: rootItemLimit }, (_, index) => ({
      ...filter(),
      filterId: `filter-${index}`,
    }));
    expect(filters.parse(filters.serialize(boundary))).toEqual(boundary);

    const oversized = JSON.stringify([...boundary, filter()]);
    const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
    expect(filters.parse(oversized)).toBeNull();
    expect(traverse).toHaveBeenCalledTimes(0);
  });

  test("filters roundtrip 256 selected values and reject 257 before any Zod array traversal", () => {
    const values = Array.from(
      { length: filterValueLimit },
      (_, index) => `value-${index}`
    );
    const boundary = [filter(values)];
    expect(filters.parse(filters.serialize(boundary))).toEqual(boundary);

    const oversized = JSON.stringify([filter([...values, "extra"])]);
    const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
    expect(filters.parse(oversized)).toBeNull();
    expect(traverse).toHaveBeenCalledTimes(0);
  });

  test("a later filter's oversized value array is refused before the root schema visits earlier invalid entries", () => {
    const raw = JSON.stringify([
      null,
      {
        ...filter(),
        value: Array.from({ length: filterValueLimit + 1 }, () => null),
      },
    ]);
    const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
    expect(filters.parse(raw)).toBeNull();
    expect(traverse).toHaveBeenCalledTimes(0);
  });

  test.each(["null", "{}", '"text"', "42", "true", "["])(
    "non-array or malformed root %s returns null",
    (raw) => {
      const traverse = jest.spyOn(z.ZodArray.prototype, "_parse");
      expect(sorting.parse(raw)).toBeNull();
      expect(filters.parse(raw)).toBeNull();
      expect(traverse).toHaveBeenCalledTimes(0);
    }
  );

  test("valid scalar, multiselect, empty and date-range filters retain their roundtrip contracts", () => {
    const value = [
      {
        ...filter("Active"),
        variant: "text" as const,
        operator: "eq" as const,
      },
      filter(["registered", "inactive"]),
      filter([]),
      {
        ...filter(["2026-01-01", "2026-11-08"]),
        variant: "dateRange" as const,
        operator: "isBetween" as const,
      },
    ];
    expect(filters.parse(filters.serialize(value))).toEqual(value);
    expect(sorting.parse("[]")).toEqual([]);
    expect(filters.parse("[]")).toEqual([]);
    expect(sorting.eq([], [])).toBe(true);
    expect(filters.eq(value, value)).toBe(true);
  });

  test.each([{ columns: ["status"] }, { columns: new Set(["status"]) }])(
    "column allowlists still govern valid sort and filter rows (%s)",
    ({ columns }) => {
      const sortParser = getSortingStateParser<{
        status: string;
        other: string;
      }>(columns);
      const filterParser = getFiltersStateParser<{
        status: string;
        other: string;
      }>(columns);
      expect(sortParser.parse('[{"id":"status","desc":true}]')).toEqual([
        { id: "status", desc: true },
      ]);
      expect(filterParser.parse(JSON.stringify([filter()]))).toEqual([
        filter(),
      ]);
      expect(sortParser.parse('[{"id":"other","desc":true}]')).toBeNull();
      expect(
        filterParser.parse(JSON.stringify([{ ...filter(), id: "other" }]))
      ).toBeNull();
    }
  );

  test("within-budget invalid scalar and nested values retain normal schema refusal", () => {
    expect(sorting.parse('[{"id":"status","desc":"false"}]')).toBeNull();
    expect(
      filters.parse(JSON.stringify([{ ...filter(), value: ["registered", 1] }]))
    ).toBeNull();
    expect(
      filters.parse(JSON.stringify([{ ...filter(), variant: "unsupported" }]))
    ).toBeNull();
  });
});
